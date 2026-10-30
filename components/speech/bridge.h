#ifndef NECTARINE_SPEECH_BRIDGE_H
#define NECTARINE_SPEECH_BRIDGE_H
#include <stdint.h>
/* Fixed-width x86-64 PE/Unix boundary. No Windows or Cocoa types here. */
enum nt_speech_op { NT_SPEECH_ENUM, NT_SPEECH_BEGIN, NT_SPEECH_READ, NT_SPEECH_END, NT_SPEECH_STATS };
struct nt_speech_voice { char id[256],name[128],language[32]; uint32_t gender; };
struct nt_speech_enum { uint64_t voices; uint32_t capacity,count; };
struct nt_speech_begin { uint64_t text,voice; uint32_t text_units; int32_t rate; uint32_t volume,reserved; uint64_t handle; };
struct nt_speech_read { uint64_t handle,buffer; uint32_t capacity,bytes,done,rate; };
struct nt_speech_end { uint64_t handle; };
struct nt_speech_stats { uint32_t created,freed; };
#endif
