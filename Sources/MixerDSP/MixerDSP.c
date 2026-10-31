#include "MixerDSP.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#define SOURCES 5
#define OUTPUTS 4
#define CAPACITY 32768
#define MASK (CAPACITY - 1)
// Every ring has exactly one capture producer and one output consumer.
// Audio callbacks allocate nothing and never acquire locks.
typedef struct {
    float samples[CAPACITY][2];
    _Atomic uint64_t write;
    _Atomic uint64_t read;
    double phase;
    int primed;
    float currentGain;
} Ring;
struct SMEngine {
    Ring rings[SOURCES][OUTPUTS];
    _Atomic float gains[SOURCES][OUTPUTS];
    _Atomic float inputGains[SOURCES];
    _Atomic double rates[SOURCES];
    _Atomic float sourcePeaks[SOURCES], outputPeaks[OUTPUTS];
    _Atomic uint64_t captures[SOURCES], renders[OUTPUTS], dropouts;
};
static void peak(_Atomic float *p, float v) {
    float old = atomic_load_explicit(p, memory_order_relaxed);
    while (v > old && !atomic_compare_exchange_weak_explicit(p, &old, v, memory_order_relaxed, memory_order_relaxed)) {}
}
SMEngine *sm_create(void) {
    SMEngine *e = calloc(1, sizeof(SMEngine));
    if (e) for (int i = 0; i < SOURCES; i++) { atomic_store(&e->inputGains[i], 1); atomic_store(&e->rates[i], 48000); }
    return e;
}
void sm_destroy(SMEngine *e) { free(e); }
void sm_set_gain(SMEngine *e, int s, int o, float g) { atomic_store(&e->gains[s][o], isfinite(g) ? g : 0); }
void sm_set_input_gain(SMEngine *e, int s, float g) { atomic_store(&e->inputGains[s], g); }
void sm_set_source_rate(SMEngine *e, int s, double r) { atomic_store(&e->rates[s], r); }
void sm_reset(SMEngine *e) { memset(e->rings, 0, sizeof(e->rings)); }
static unsigned frames(const AudioBufferList *b) {
    if (!b || !b->mNumberBuffers || !b->mBuffers[0].mNumberChannels) return 0;
    return b->mBuffers[0].mDataByteSize / (sizeof(float) * b->mBuffers[0].mNumberChannels);
}
static float sample(const AudioBufferList *b, unsigned frame, int channel) {
    for (unsigned j = 0; j < b->mNumberBuffers; j++) {
        const AudioBuffer *v = &b->mBuffers[j];
        if (channel < (int)v->mNumberChannels) {
            if (!v->mData || (frame * v->mNumberChannels + channel + 1) * sizeof(float) > v->mDataByteSize) return 0;
            float value = ((float *)v->mData)[frame * v->mNumberChannels + channel];
            return isfinite(value) ? value : 0;
        }
        channel -= v->mNumberChannels;
    }
    return 0;
}
static void put(AudioBufferList *b, unsigned frame, int channel, float value) {
    for (unsigned j = 0; j < b->mNumberBuffers; j++) {
        AudioBuffer *v = &b->mBuffers[j];
        if (channel < (int)v->mNumberChannels) {
            if (v->mData && (frame * v->mNumberChannels + channel + 1) * sizeof(float) <= v->mDataByteSize)
                ((float *)v->mData)[frame * v->mNumberChannels + channel] = value;
            return;
        }
        channel -= v->mNumberChannels;
    }
}
void sm_capture(SMEngine *e, int s, const AudioBufferList *b, int channel, int stereo) {
    unsigned n = frames(b); if (!n) return;
    atomic_fetch_add(&e->captures[s], 1);
    float p = 0, inputGain = atomic_load(&e->inputGains[s]);
    uint64_t writes[OUTPUTS]; int canWrite[OUTPUTS];
    for (int o = 0; o < OUTPUTS; o++) {
        Ring *r = &e->rings[s][o]; writes[o] = atomic_load_explicit(&r->write, memory_order_relaxed);
        canWrite[o] = n < CAPACITY && writes[o] - atomic_load_explicit(&r->read, memory_order_acquire) + n < CAPACITY;
        // Inactive outputs can fill; do not count them as an audible overrun.
        if (!canWrite[o] && atomic_load(&e->gains[s][o]) > 0) atomic_fetch_add(&e->dropouts, 1);
    }
    for (unsigned f = 0; f < n; f++) {
        float l = sample(b, f, channel), rr = stereo ? sample(b, f, channel + 1) : l;
        p = fmaxf(p, fmaxf(fabsf(l), fabsf(rr)) * inputGain);
        for (int o = 0; o < OUTPUTS; o++) if (canWrite[o]) {
            e->rings[s][o].samples[(writes[o] + f) & MASK][0] = l;
            e->rings[s][o].samples[(writes[o] + f) & MASK][1] = rr;
        }
    }
    for (int o = 0; o < OUTPUTS; o++) if (canWrite[o]) atomic_store_explicit(&e->rings[s][o].write, writes[o] + n, memory_order_release);
    peak(&e->sourcePeaks[s], p);
}
void sm_render(SMEngine *e, int o, AudioBufferList *b, double rate) {
    unsigned n = frames(b); if (!n || rate <= 0) return;
    for (unsigned j = 0; j < b->mNumberBuffers; j++) if (b->mBuffers[j].mData) memset(b->mBuffers[j].mData, 0, b->mBuffers[j].mDataByteSize);
    atomic_fetch_add(&e->renders[o], 1);
    // Fixed-size chunks avoid allocation even for unusually large hardware buffers.
    float mix[256][2]; float outputPeak = 0;
    for (unsigned base = 0; base < n; base += 256) {
        unsigned count = n - base < 256 ? n - base : 256; memset(mix, 0, sizeof(mix));
        for (int s = 0; s < SOURCES; s++) {
            Ring *r = &e->rings[s][o];
            uint64_t w = atomic_load_explicit(&r->write, memory_order_acquire), rd = atomic_load_explicit(&r->read, memory_order_relaxed);
            double ratio = atomic_load(&e->rates[s]) / rate;
            uint64_t target = (uint64_t)fmax(512, atomic_load(&e->rates[s]) * .012);
            float gain = atomic_load(&e->gains[s][o]);
            // Discard stale audio after a stopped consumer or long scheduling pause.
            if (w - rd > target * 4) { rd = w - target; r->phase = 0; r->primed = 1; }
            if (!r->primed && w - rd >= target) r->primed = 1;
            if (!r->primed) continue;
            // Small occupancy correction accommodates independent device clocks.
            double correction = fmax(-.005, fmin(.005, ((double)(w - rd) - target) / (target * 200.0)));
            ratio *= 1 + correction;
            if (gain == 0) r->currentGain = 0; // Mute must not leak a fade-out tail.
            for (unsigned f = 0; f < count; f++) {
                if (rd + 1 >= w) { r->primed = 0; if (gain > 0) atomic_fetch_add(&e->dropouts, 1); break; }
                if (gain > 0) r->currentGain += (gain - r->currentGain) * .008f;
                for (int c = 0; c < 2; c++) {
                    float a = r->samples[rd & MASK][c], bb = r->samples[(rd + 1) & MASK][c];
                    mix[f][c] += (a + (bb - a) * r->phase) * r->currentGain;
                }
                r->phase += ratio; uint64_t step = (uint64_t)r->phase; r->phase -= step;
                rd += step; if (rd > w) rd = w;
            }
            atomic_store_explicit(&r->read, rd, memory_order_release);
        }
        for (unsigned f = 0; f < count; f++) for (int c = 0; c < 2; c++) {
            outputPeak = fmaxf(outputPeak, fabsf(mix[f][c]));
            put(b, base + f, c, fmaxf(-1, fminf(1, mix[f][c])));
        }
    }
    peak(&e->outputPeaks[o], outputPeak);
}
float sm_take_source_peak(SMEngine *e, int s) { return atomic_exchange(&e->sourcePeaks[s], 0); }
float sm_take_output_peak(SMEngine *e, int o) { return atomic_exchange(&e->outputPeaks[o], 0); }
uint64_t sm_dropouts(SMEngine *e) { return atomic_load(&e->dropouts); }
uint64_t sm_capture_count(SMEngine *e, int s) { return atomic_load(&e->captures[s]); }
uint64_t sm_render_count(SMEngine *e, int o) { return atomic_load(&e->renders[o]); }
