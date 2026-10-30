/* Exercises the Windows-facing SAPI provider without playing sound. */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <sapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "bridge.h"
static const GUID wave_format={0xc31adbae,0x527f,0x4ff5,{0xa2,0x30,0xf6,0x2b,0xb6,0x1f,0xf7,0x0c}};
typedef HRESULT(WINAPI *stats_fn)(struct nt_speech_stats*);
typedef HRESULT(WINAPI *unload_fn)(void);
static int speak_case(ISpVoice *voice,const WCHAR *text,const char *name) {
    IStream *memory=NULL;ISpStream *stream=NULL;
    WAVEFORMATEX format={WAVE_FORMAT_PCM,1,22050,44100,2,16,0};
    HRESULT hr=CreateStreamOnHGlobal(NULL,TRUE,&memory);SPVOICESTATUS before={0},after={0};ULONG number=0;
    if(SUCCEEDED(hr))hr=CoCreateInstance(&CLSID_SpStream,NULL,CLSCTX_INPROC_SERVER,&IID_ISpStream,(void**)&stream);
    if(SUCCEEDED(hr))hr=ISpStream_SetBaseStream(stream,memory,&wave_format,&format);
    if(SUCCEEDED(hr))hr=ISpVoice_SetOutput(voice,(IUnknown*)stream,FALSE);
    if(SUCCEEDED(hr))hr=ISpVoice_Speak(voice,text,SPF_ASYNC,&number);
    if(SUCCEEDED(hr))hr=ISpVoice_GetStatus(voice,&before,NULL);
    if(SUCCEEDED(hr))hr=ISpVoice_WaitUntilDone(voice,20000);
    if(SUCCEEDED(hr))hr=ISpVoice_GetStatus(voice,&after,NULL);
    STATSTG info={0};if(memory)IStream_Stat(memory,&info,STATFLAG_NONAME);
    ULONG read=0,nonzero=0;BYTE *pcm=NULL;
    if(info.cbSize.QuadPart&&info.cbSize.QuadPart<16*1024*1024) {
        pcm=malloc((size_t)info.cbSize.QuadPart);LARGE_INTEGER zero={0};
        IStream_Seek(memory,zero,STREAM_SEEK_SET,NULL);IStream_Read(memory,pcm,(ULONG)info.cbSize.QuadPart,&read);
        for(ULONG i=0;i<read;i++)if(pcm[i])nonzero++;
    }
    int fail=FAILED(hr)||!read||!nonzero||after.dwRunningState!=SPRS_DONE;
    printf("SAPI_CASE %s hr=%08lx stream=%lu before=%lu after=%lu last_result=%08lx bytes=%lu nonzero=%lu result=%s\n",
           name,hr,number,before.dwRunningState,after.dwRunningState,after.hrLastResult,read,nonzero,fail?"FAIL":"PASS");
    free(pcm);if(stream)ISpStream_Release(stream);if(memory)IStream_Release(memory);return fail;
}
int main(void) {
    HRESULT hr=CoInitializeEx(NULL,COINIT_MULTITHREADED);if(FAILED(hr))return 1;
    HMODULE module=LoadLibraryA("nectarinetts.dll");if(!module)return 2;
    stats_fn stats=(stats_fn)GetProcAddress(module,"NectarineSpeechJobStats");
    unload_fn unload=(unload_fn)GetProcAddress(module,"DllCanUnloadNow");
    if(!stats||!unload)return 3;
    printf("SAPI_UNLOAD before=%08lx\n",unload());
    ISpVoice *voice=NULL;ISpObjectToken *token=NULL;IEnumSpObjectTokens *voices=NULL;int fail=0;
    hr=CoCreateInstance(&CLSID_SpVoice,NULL,CLSCTX_INPROC_SERVER,&IID_ISpVoice,(void**)&voice);
    if(FAILED(hr))return 4;
    hr=ISpVoice_GetVoice(voice,&token);WCHAR *id=NULL;if(token)ISpObjectToken_GetId(token,&id);
    printf("SAPI_DEFAULT hr=%08lx id=%ls\n",hr,id?id:L"null");
    if(FAILED(hr)||!id||!wcsstr(id,L"Nectarine"))fail++;
    CoTaskMemFree(id);if(token)ISpObjectToken_Release(token);token=NULL;
    fail+=speak_case(voice,L"Nectarine speech library test.","default");
    fail+=speak_case(voice,L"Repeated speech must finish and preserve status.","repeat");
    printf("SAPI_UNLOAD active=%08lx\n",unload());if(unload()!=S_FALSE)fail++;
    ISpObjectTokenCategory *category=NULL;
    hr=CoCreateInstance(&CLSID_SpObjectTokenCategory,NULL,CLSCTX_INPROC_SERVER,&IID_ISpObjectTokenCategory,(void**)&category);
    if(SUCCEEDED(hr))hr=ISpObjectTokenCategory_SetId(category,SPCAT_VOICES,FALSE);
    if(SUCCEEDED(hr))hr=ISpObjectTokenCategory_EnumTokens(category,L"Language=409",NULL,&voices);
    if(category)ISpObjectTokenCategory_Release(category);
    ULONG count=0;if(voices)IEnumSpObjectTokens_GetCount(voices,&count);
    BOOL selected=FALSE;
    for(ULONG i=0;i<count;i++) {
        ULONG fetched=0;ISpObjectToken *candidate=NULL;WCHAR *name=NULL;
        if(FAILED(IEnumSpObjectTokens_Next(voices,1,&candidate,&fetched))||!fetched)break;
        ISpObjectToken_GetId(candidate,&name);
        if(name&&wcsstr(name,L"Nectarine")&&!wcsstr(name,L"Samantha")) {
            hr=ISpVoice_SetVoice(voice,candidate);printf("SAPI_SELECT hr=%08lx id=%ls\n",hr,name);selected=SUCCEEDED(hr);
        }
        CoTaskMemFree(name);ISpObjectToken_Release(candidate);if(selected)break;
    }
    if(voices)IEnumSpObjectTokens_Release(voices);
    if(!selected)fail++;
    ISpVoice_SetRate(voice,2);ISpVoice_SetVolume(voice,50);
    fail+=speak_case(voice,L"A second native voice works at a different rate and volume.","selected");
    struct nt_speech_stats pre={0},post={0};stats(&pre);
    WCHAR long_text[8192];long_text[0]=0;for(unsigned i=0;i<100;i++)wcscat(long_text,L"This is a cancellation test for the native speech provider. ");
    hr=ISpVoice_Speak(voice,long_text,SPF_ASYNC,NULL);
    DWORD started=GetTickCount();
    while(SUCCEEDED(hr)&&GetTickCount()-started<2000){stats(&post);if(post.created>pre.created)break;Sleep(10);}
    BOOL begun=post.created>pre.created;
    if(SUCCEEDED(hr))hr=ISpVoice_Speak(voice,NULL,SPF_ASYNC|SPF_PURGEBEFORESPEAK,NULL);
    if(SUCCEEDED(hr))hr=ISpVoice_WaitUntilDone(voice,10000);
    SPVOICESTATUS state={0};ISpVoice_GetStatus(voice,&state,NULL);
    DWORD idle_started=GetTickCount();
    while(SUCCEEDED(hr)&&state.dwRunningState!=SPRS_DONE&&GetTickCount()-idle_started<5000) {
        Sleep(100);ISpVoice_GetStatus(voice,&state,NULL);
    }
    stats(&post);
    printf("SAPI_ABORT hr=%08lx begun=%u state=%lu created=%u freed=%u\n",hr,begun,state.dwRunningState,post.created,post.freed);
    if(FAILED(hr)||!begun||state.dwRunningState!=SPRS_DONE||post.created!=post.freed)fail++;
    ISpVoice_Release(voice);
    started=GetTickCount();do{stats(&post);if(post.created==post.freed)break;Sleep(20);}while(GetTickCount()-started<2000);
    printf("SAPI_JOBS created=%u freed=%u unload=%08lx\n",post.created,post.freed,unload());
    if(post.created!=post.freed||unload()!=S_OK)fail++;
    FreeLibrary(module);CoUninitialize();printf("SAPI_INTEGRATION failures=%d\n",fail);return fail?1:0;
}
