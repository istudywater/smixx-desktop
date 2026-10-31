#pragma once
#include <CoreAudio/CoreAudio.h>
#include <stdint.h>
typedef struct SMEngine SMEngine;
SMEngine *sm_create(void);
void sm_destroy(SMEngine *engine);
void sm_set_gain(SMEngine *, int source, int output, float gain);
void sm_set_input_gain(SMEngine *, int source, float gain);
void sm_set_source_rate(SMEngine *, int source, double rate);
// Call reset only after stopping the source AND all output callbacks.
void sm_reset(SMEngine *);
void sm_capture(SMEngine *, int source, const AudioBufferList *, int channel, int stereo);
void sm_render(SMEngine *, int output, AudioBufferList *, double rate);
float sm_take_source_peak(SMEngine *, int source);
float sm_take_output_peak(SMEngine *, int output);
uint64_t sm_dropouts(SMEngine *);
uint64_t sm_capture_count(SMEngine *, int source);
uint64_t sm_render_count(SMEngine *, int output);
