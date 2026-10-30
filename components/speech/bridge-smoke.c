#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include "bridge.h"
extern uint64_t __wine_unixlib_handle;
extern LONG WINAPI __wine_init_unix_call(void);
extern LONG (WINAPI *__wine_unix_call_dispatcher)(uint64_t,unsigned,void*);
__declspec(dllexport) int __cdecl NectarineSpeechEnumerate(void) {
    struct nt_speech_voice voices[128];
    struct nt_speech_enum arg={(uint64_t)(uintptr_t)voices,128,0};
    LONG status=__wine_init_unix_call();
    printf("NATIVE_SPEECH_UNIX_INIT status=%08lx handle=%llu\n",status,(unsigned long long)__wine_unixlib_handle);
    if(status)return 1;
    status=__wine_unix_call_dispatcher(__wine_unixlib_handle,NT_SPEECH_ENUM,&arg);
    printf("NATIVE_SPEECH_ENUM status=%08lx count=%u\n",status,arg.count);
    for(uint32_t i=0;i<arg.count && i<arg.capacity;i++)printf("VOICE id=%s name=%s language=%s\n",voices[i].id,voices[i].name,voices[i].language);
    if(status || !arg.count)return 1;
    const WCHAR text[]=L"Nectarine speech library test.";
    struct nt_speech_begin begin={(uint64_t)(uintptr_t)text,(uint64_t)(uintptr_t)voices[0].id,sizeof(text)/2-1,0,100,0,0};
    status=__wine_unix_call_dispatcher(__wine_unixlib_handle,NT_SPEECH_BEGIN,&begin);
    printf("NATIVE_SPEECH_BEGIN status=%08lx handle=%llu\n",status,(unsigned long long)begin.handle);
    if(status)return 1;
    BYTE pcm[8192];unsigned bytes=0,nonzero=0;DWORD start=GetTickCount();
    struct nt_speech_read read={begin.handle,(uint64_t)(uintptr_t)pcm,sizeof(pcm),0,0,0};
    while(!read.done && GetTickCount()-start<15000) {
        status=__wine_unix_call_dispatcher(__wine_unixlib_handle,NT_SPEECH_READ,&read);
        if(status)break;
        bytes+=read.bytes;
        for(unsigned i=0;i<read.bytes;i++)if(pcm[i])nonzero++;
    }
    struct nt_speech_end end={begin.handle};
    __wine_unix_call_dispatcher(__wine_unixlib_handle,NT_SPEECH_END,&end);
    printf("NATIVE_SPEECH_PCM status=%08lx bytes=%u nonzero=%u done=%u rate=%u\n",status,bytes,nonzero,read.done,read.rate);
    return status!=0 || !read.done || !bytes || !nonzero;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved){(void)module;(void)reason;(void)reserved;return TRUE;}
