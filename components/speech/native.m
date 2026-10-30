#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include "bridge.h"
#include <string.h>
#include <math.h>
#include <stdatomic.h>
static _Atomic uint32_t jobs_created,jobs_freed;

@interface NTSpeechJob : NSObject
@property AVSpeechSynthesizer *synth;
@property AVAudioConverter *converter;
@property NSCondition *condition;
@property NSMutableData *audio;
@property NSUInteger offset;
@property BOOL done,cancelled,failed;
@end
@implementation NTSpeechJob
- (void)dealloc { atomic_fetch_add(&jobs_freed,1); }
@end

static void convert_audio(NTSpeechJob *job,AVAudioPCMBuffer *input,BOOL final) {
    if(!job.converter && input.frameLength) {
        AVAudioFormat *output=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:22050 channels:1 interleaved:NO];
        job.converter=[[AVAudioConverter alloc] initFromFormat:input.format toFormat:output];
    }
    if(!job.converter)return;
    AVAudioFrameCount capacity=final?1024:(AVAudioFrameCount)(input.frameLength*22050/input.format.sampleRate+1024);
    AVAudioPCMBuffer *output=[[AVAudioPCMBuffer alloc] initWithPCMFormat:job.converter.outputFormat frameCapacity:capacity];
    __block BOOL supplied=NO;
    NSError *error=nil;
    AVAudioConverterOutputStatus status=[job.converter convertToBuffer:output error:&error withInputFromBlock:^AVAudioBuffer*(AVAudioPacketCount count,AVAudioConverterInputStatus *state){
        (void)count;
        if(final){*state=AVAudioConverterInputStatus_EndOfStream;return nil;}
        if(supplied){*state=AVAudioConverterInputStatus_NoDataNow;return nil;}
        supplied=YES;*state=AVAudioConverterInputStatus_HaveData;return input;
    }];
    if(status==AVAudioConverterOutputStatus_Error){job.failed=YES;job.done=YES;return;}
    if(output.frameLength) {
        NSMutableData *pcm=[NSMutableData dataWithLength:output.frameLength*sizeof(int16_t)];
        int16_t *dst=pcm.mutableBytes;float *src=output.floatChannelData[0];
        for(AVAudioFrameCount i=0;i<output.frameLength;i++)dst[i]=(int16_t)lrintf(fmaxf(-1,fminf(1,src[i]))*32767);
        [job.audio appendData:pcm];
    }
}

static int32_t enumerate(void *args) {
    struct nt_speech_enum *a=args;
    struct nt_speech_voice *out=(void*)(uintptr_t)a->voices;
    @autoreleasepool {
        NSArray<AVSpeechSynthesisVoice*> *voices=[AVSpeechSynthesisVoice speechVoices];
        a->count=(uint32_t)voices.count;
        for(uint32_t i=0;i<a->capacity && i<a->count;i++) {
            AVSpeechSynthesisVoice *voice=voices[i];
            memset(&out[i],0,sizeof(out[i]));
            snprintf(out[i].id,sizeof(out[i].id),"%s",voice.identifier.UTF8String);
            snprintf(out[i].name,sizeof(out[i].name),"%s",voice.name.UTF8String);
            snprintf(out[i].language,sizeof(out[i].language),"%s",voice.language.UTF8String);
            out[i].gender=(uint32_t)voice.gender;
        }
    }
    return 0;
}
static int32_t begin_speech(void *args) {
    struct nt_speech_begin *a=args;
    @autoreleasepool {
        NSString *text=[[NSString alloc] initWithCharacters:(const unichar*)(uintptr_t)a->text length:a->text_units];
        NSString *identifier=[NSString stringWithUTF8String:(const char*)(uintptr_t)a->voice];
        AVSpeechSynthesisVoice *voice=[AVSpeechSynthesisVoice voiceWithIdentifier:identifier];
        if(!voice || !text)return (int32_t)0xc000000d;
        NTSpeechJob *job=[NTSpeechJob new];job.synth=[AVSpeechSynthesizer new];
        job.condition=[NSCondition new];job.audio=[NSMutableData data];
        AVSpeechUtterance *utterance=[[AVSpeechUtterance alloc] initWithString:text];
        utterance.voice=voice;
        utterance.rate=fmaxf(AVSpeechUtteranceMinimumSpeechRate,fminf(AVSpeechUtteranceMaximumSpeechRate,AVSpeechUtteranceDefaultSpeechRate*powf(2.0f,a->rate/10.0f)));
        utterance.volume=fminf(1,a->volume/100.0f);
        a->handle=(uint64_t)(uintptr_t)CFBridgingRetain(job);
        atomic_fetch_add(&jobs_created,1);
        __weak NTSpeechJob *weak_job=job;
        [job.synth writeUtterance:utterance toBufferCallback:^(AVAudioBuffer *buffer){
            @autoreleasepool {
                NTSpeechJob *job=weak_job;
                if(!job)return;
                [job.condition lock];
                if(!job.cancelled && [buffer isKindOfClass:[AVAudioPCMBuffer class]]) {
                    AVAudioPCMBuffer *pcm=(AVAudioPCMBuffer*)buffer;
                    convert_audio(job,pcm,!pcm.frameLength);
                    if(!pcm.frameLength)job.done=YES;
                }
                [job.condition broadcast];[job.condition unlock];
            }
        }];
    }
    return 0;
}
static int32_t read_speech(void *args) {
    struct nt_speech_read *a=args;
    NTSpeechJob *job=(__bridge NTSpeechJob*)(void*)(uintptr_t)a->handle;
    if(!job)return (int32_t)0xc000000d;
    @autoreleasepool {
        [job.condition lock];
        if(job.offset==job.audio.length&&!job.done&&!job.cancelled)
            [job.condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        a->bytes=(uint32_t)MIN(a->capacity,job.audio.length-job.offset);
        if(a->bytes)memcpy((void*)(uintptr_t)a->buffer,(const char*)job.audio.bytes+job.offset,a->bytes);
        job.offset+=a->bytes;
        a->done=(job.done||job.cancelled)&&job.offset==job.audio.length;
        a->rate=22050;
        BOOL failed=job.failed;
        [job.condition unlock];
        return failed?(int32_t)0xc0000001:0;
    }
}
static int32_t end_speech(void *args) {
    struct nt_speech_end *a=args;
    NTSpeechJob *job=CFBridgingRelease((void*)(uintptr_t)a->handle);
    if(!job)return (int32_t)0xc000000d;
    [job.condition lock];job.cancelled=YES;[job.condition broadcast];[job.condition unlock];
    [job.synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
    return 0;
}
static int32_t stats(void *args) {
    struct nt_speech_stats *a=args;a->created=atomic_load(&jobs_created);a->freed=atomic_load(&jobs_freed);return 0;
}
__attribute__((visibility("default"))) int32_t(*const __wine_unix_call_funcs[])(void*)={enumerate,begin_speech,read_speech,end_speech,stats};
