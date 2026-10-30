/* Native macOS SAPI TTS provider; candidate-only Wine builtin DLL. */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <sapiddk.h>
#include <sperror.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "bridge.h"

DEFINE_GUID(CLSID_NectarineSpeech,0xe137cb12,0xaa45,0x4f5d,0xa4,0x26,0x41,0xda,0xf6,0xb3,0xe9,0x09);
static const WCHAR class_id[]=L"{E137CB12-AA45-4F5D-A426-41DAF6B3E909}";
static const GUID wave_format={0xc31adbae,0x527f,0x4ff5,{0xa2,0x30,0xf6,0x2b,0xb6,0x1f,0xf7,0x0c}};
extern uint64_t __wine_unixlib_handle;
extern LONG WINAPI __wine_init_unix_call(void);
extern LONG (WINAPI *__wine_unix_call_dispatcher)(uint64_t,unsigned,void*);
static INIT_ONCE native_once=INIT_ONCE_STATIC_INIT;
static LONG native_status;
static HINSTANCE instance;
static LONG objects,locks;
static BOOL CALLBACK init_native(INIT_ONCE *once,void *param,void **context) {
    (void)once;(void)param;(void)context;native_status=__wine_init_unix_call();return TRUE;
}
static HRESULT native(unsigned op,void *args) {
    InitOnceExecuteOnce(&native_once,init_native,NULL,NULL);
    if(native_status)return HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED);
    LONG status=__wine_unix_call_dispatcher(__wine_unixlib_handle,op,args);
    return status?HRESULT_FROM_WIN32(status==(LONG)0xc000000d?ERROR_INVALID_PARAMETER:ERROR_GEN_FAILURE):S_OK;
}
typedef struct {
    ISpTTSEngine engine;
    ISpObjectWithToken token_iface;
    LONG refs;
    ISpObjectToken *token;
    char voice[256];
} Speech;
static Speech *from_engine(ISpTTSEngine *iface){return CONTAINING_RECORD(iface,Speech,engine);}
static Speech *from_token(ISpObjectWithToken *iface){return CONTAINING_RECORD(iface,Speech,token_iface);}
static HRESULT WINAPI engine_query(ISpTTSEngine *iface,REFIID iid,void **out) {
    Speech *self=from_engine(iface);
    if(!out)return E_POINTER;*out=NULL;
    if(IsEqualIID(iid,&IID_IUnknown)||IsEqualIID(iid,&IID_ISpTTSEngine))*out=&self->engine;
    else if(IsEqualIID(iid,&IID_ISpObjectWithToken))*out=&self->token_iface;
    else return E_NOINTERFACE;
    InterlockedIncrement(&self->refs);return S_OK;
}
static ULONG WINAPI engine_addref(ISpTTSEngine *iface){return InterlockedIncrement(&from_engine(iface)->refs);}
static ULONG WINAPI engine_release(ISpTTSEngine *iface) {
    Speech *self=from_engine(iface);LONG refs=InterlockedDecrement(&self->refs);
    if(!refs){if(self->token)ISpObjectToken_Release(self->token);HeapFree(GetProcessHeap(),0,self);InterlockedDecrement(&objects);}
    return refs;
}
static HRESULT write_all(ISpTTSEngineSite *site,const BYTE *data,ULONG size) {
    while(size) {
        ULONG written=0;HRESULT hr;
        if(ISpTTSEngineSite_GetActions(site)&SPVES_ABORT)return S_FALSE;
        hr=ISpTTSEngineSite_Write(site,data,size,&written);
        if(FAILED(hr))return hr;
        if(!written||written>size)return E_FAIL;
        data+=written;size-=written;
    }
    return S_OK;
}
static HRESULT WINAPI engine_speak(ISpTTSEngine *iface,DWORD flags,REFGUID id,
                                   const WAVEFORMATEX *format,const SPVTEXTFRAG *frag,ISpTTSEngineSite *site) {
    Speech *self=from_engine(iface);BYTE pcm[8192];HRESULT hr=S_OK;
    (void)flags;
    if(!site||!format||!id)return E_POINTER;
    if(!IsEqualGUID(id,&wave_format)||format->wFormatTag!=WAVE_FORMAT_PCM||format->nChannels!=1||
       format->nSamplesPerSec!=22050||format->wBitsPerSample!=16)return SPERR_UNSUPPORTED_FORMAT;
    if(!self->voice[0])return SPERR_UNINITIALIZED;
    for(;frag;frag=frag->pNext) {
        LONG rate=0;USHORT volume=100;
        if(ISpTTSEngineSite_GetActions(site)&SPVES_ABORT)return S_OK;
        if(frag->State.eAction==SPVA_Silence) {
            uint64_t left=(uint64_t)frag->State.SilenceMSecs*22050/1000*2;
            memset(pcm,0,sizeof(pcm));
            while(left){ULONG n=left>sizeof(pcm)?sizeof(pcm):(ULONG)left;hr=write_all(site,pcm,n);if(hr!=S_OK)return hr==S_FALSE?S_OK:hr;left-=n;}
            continue;
        }
        if(frag->State.eAction!=SPVA_Speak)return E_NOTIMPL;
        if(!frag->ulTextLen)continue;
        ISpTTSEngineSite_GetRate(site,&rate);ISpTTSEngineSite_GetVolume(site,&volume);
        rate+=frag->State.RateAdj;if(rate<-10)rate=-10;if(rate>10)rate=10;
        struct nt_speech_begin begin={(uint64_t)(uintptr_t)frag->pTextStart,(uint64_t)(uintptr_t)self->voice,
            frag->ulTextLen,rate,(uint32_t)volume*frag->State.Volume/100,0,0};
        hr=native(NT_SPEECH_BEGIN,&begin);if(FAILED(hr))return hr;
        struct nt_speech_read read={begin.handle,(uint64_t)(uintptr_t)pcm,sizeof(pcm),0,0,0};
        DWORD started=GetTickCount();
        while(!read.done) {
            if(ISpTTSEngineSite_GetActions(site)&SPVES_ABORT){hr=S_FALSE;break;}
            if(GetTickCount()-started>120000){hr=HRESULT_FROM_WIN32(ERROR_TIMEOUT);break;}
            hr=native(NT_SPEECH_READ,&read);if(FAILED(hr))break;
            if(read.bytes){hr=write_all(site,pcm,read.bytes);if(hr!=S_OK)break;}
        }
        struct nt_speech_end end={begin.handle};native(NT_SPEECH_END,&end);
        if(hr!=S_OK)return hr==S_FALSE?S_OK:hr;
    }
    return S_OK;
}
static HRESULT WINAPI engine_format(ISpTTSEngine *iface,const GUID *target,const WAVEFORMATEX *wanted,
                                    GUID *id,WAVEFORMATEX **out) {
    (void)iface;(void)target;(void)wanted;
    if(!id||!out)return E_POINTER;*out=CoTaskMemAlloc(sizeof(**out));if(!*out)return E_OUTOFMEMORY;
    **out=(WAVEFORMATEX){WAVE_FORMAT_PCM,1,22050,44100,2,16,0};*id=wave_format;return S_OK;
}
static const ISpTTSEngineVtbl engine_vtbl={engine_query,engine_addref,engine_release,engine_speak,engine_format};
static HRESULT WINAPI token_query(ISpObjectWithToken *iface,REFIID iid,void **out){return engine_query(&from_token(iface)->engine,iid,out);}
static ULONG WINAPI token_addref(ISpObjectWithToken *iface){return engine_addref(&from_token(iface)->engine);}
static ULONG WINAPI token_release(ISpObjectWithToken *iface){return engine_release(&from_token(iface)->engine);}
static HRESULT WINAPI token_set(ISpObjectWithToken *iface,ISpObjectToken *token) {
    Speech *self=from_token(iface);WCHAR *id=NULL;char utf8[256];HRESULT hr;
    if(!token)return E_INVALIDARG;
    if(self->token)return SPERR_ALREADY_INITIALIZED;
    hr=ISpObjectToken_GetStringValue(token,L"NativeVoiceId",&id);if(FAILED(hr))return hr;
    int n=WideCharToMultiByte(CP_UTF8,0,id,-1,utf8,sizeof(utf8),NULL,NULL);CoTaskMemFree(id);
    if(!n)return HRESULT_FROM_WIN32(GetLastError());
    memcpy(self->voice,utf8,n);ISpObjectToken_AddRef(token);self->token=token;return S_OK;
}
static HRESULT WINAPI token_get(ISpObjectWithToken *iface,ISpObjectToken **token) {
    Speech *self=from_token(iface);if(!token)return E_POINTER;*token=self->token;
    if(!*token)return SPERR_UNINITIALIZED;ISpObjectToken_AddRef(*token);return S_OK;
}
static const ISpObjectWithTokenVtbl token_vtbl={token_query,token_addref,token_release,token_set,token_get};
static HRESULT WINAPI factory_query(IClassFactory *iface,REFIID iid,void **out) {
    if(!out)return E_POINTER;*out=NULL;
    if(!IsEqualIID(iid,&IID_IUnknown)&&!IsEqualIID(iid,&IID_IClassFactory))return E_NOINTERFACE;
    *out=iface;IClassFactory_AddRef(iface);return S_OK;
}
static ULONG WINAPI factory_addref(IClassFactory *iface){(void)iface;return 2;}
static ULONG WINAPI factory_release(IClassFactory *iface){(void)iface;return 1;}
static HRESULT WINAPI factory_create(IClassFactory *iface,IUnknown *outer,REFIID iid,void **out) {
    (void)iface;if(!out)return E_POINTER;*out=NULL;if(outer)return CLASS_E_NOAGGREGATION;
    Speech *self=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,sizeof(*self));if(!self)return E_OUTOFMEMORY;
    self->engine.lpVtbl=&engine_vtbl;self->token_iface.lpVtbl=&token_vtbl;self->refs=1;InterlockedIncrement(&objects);
    HRESULT hr=engine_query(&self->engine,iid,out);engine_release(&self->engine);return hr;
}
static HRESULT WINAPI factory_lock(IClassFactory *iface,BOOL lock){(void)iface;if(lock)InterlockedIncrement(&locks);else InterlockedDecrement(&locks);return S_OK;}
static const IClassFactoryVtbl factory_vtbl={factory_query,factory_addref,factory_release,factory_create,factory_lock};
static IClassFactory factory={&factory_vtbl};
__declspec(dllexport) HRESULT WINAPI DllGetClassObject(REFCLSID clsid,REFIID iid,void **out) {
    if(!IsEqualCLSID(clsid,&CLSID_NectarineSpeech)){if(out)*out=NULL;return CLASS_E_CLASSNOTAVAILABLE;}
    return factory_query(&factory,iid,out);
}
__declspec(dllexport) HRESULT WINAPI DllCanUnloadNow(void){return objects||locks?S_FALSE:S_OK;}
__declspec(dllexport) HRESULT WINAPI NectarineSpeechJobStats(struct nt_speech_stats *out){return out?native(NT_SPEECH_STATS,out):E_POINTER;}
static HRESULT reg_string(const WCHAR *key,const WCHAR *name,const WCHAR *value) {
    HKEY opened;LONG err=RegCreateKeyExW(HKEY_LOCAL_MACHINE,key,0,NULL,0,KEY_SET_VALUE,NULL,&opened,NULL);
    if(err)return HRESULT_FROM_WIN32(err);
    err=RegSetValueExW(opened,name,0,REG_SZ,(const BYTE*)value,(lstrlenW(value)+1)*sizeof(WCHAR));RegCloseKey(opened);
    return err?HRESULT_FROM_WIN32(err):S_OK;
}
__declspec(dllexport) HRESULT WINAPI DllRegisterServer(void) {
    WCHAR key[1024],value[1024],path[MAX_PATH],first[1024]=L"";HRESULT hr;
    struct nt_speech_enum enumeration={0,0,0};hr=native(NT_SPEECH_ENUM,&enumeration);if(FAILED(hr))return hr;
    if(!enumeration.count || enumeration.count>4096)return E_FAIL;
    struct nt_speech_voice *voices=HeapAlloc(GetProcessHeap(),HEAP_ZERO_MEMORY,enumeration.count*sizeof(*voices));
    if(!voices)return E_OUTOFMEMORY;
    enumeration.voices=(uint64_t)(uintptr_t)voices;enumeration.capacity=enumeration.count;
    hr=native(NT_SPEECH_ENUM,&enumeration);if(FAILED(hr))goto done;
    GetModuleFileNameW(instance,path,MAX_PATH);
    swprintf(key,1024,L"Software\\Classes\\CLSID\\%ls\\InprocServer32",class_id);
    if(FAILED(hr=reg_string(key,NULL,path)))goto done;
    if(FAILED(hr=reg_string(key,L"ThreadingModel",L"Both")))goto done;
    for(uint32_t i=0;i<enumeration.count && i<enumeration.capacity;i++) {
        WCHAR identifier[256],name[128],language[32],base[768];
        MultiByteToWideChar(CP_UTF8,0,voices[i].id,-1,identifier,256);
        MultiByteToWideChar(CP_UTF8,0,voices[i].name,-1,name,128);
        MultiByteToWideChar(CP_UTF8,0,voices[i].language,-1,language,32);
        swprintf(base,768,L"Software\\Microsoft\\Speech\\Voices\\Tokens\\Nectarine %ls",identifier);
        if(FAILED(hr=reg_string(base,NULL,name)) || FAILED(hr=reg_string(base,L"CLSID",class_id)) ||
           FAILED(hr=reg_string(base,L"NativeVoiceId",identifier)))goto done;
        swprintf(key,1024,L"%ls\\Attributes",base);
        if(FAILED(hr=reg_string(key,L"Name",name)) || FAILED(hr=reg_string(key,L"Vendor",L"Nectarine")) ||
           FAILED(hr=reg_string(key,L"Gender",voices[i].gender==1?L"Male":voices[i].gender==2?L"Female":L"Neutral")))goto done;
        LCID locale=LocaleNameToLCID(language,LOCALE_ALLOW_NEUTRAL_NAMES);
        swprintf(value,1024,L"%lx",locale?locale:0x409);
        if(FAILED(hr=reg_string(key,L"Language",value)))goto done;
        if(!first[0] || !strcmp(voices[i].id,"com.apple.voice.compact.en-US.Samantha"))
            swprintf(first,1024,L"HKEY_LOCAL_MACHINE\\%ls",base);
    }
    hr=reg_string(L"Software\\Microsoft\\Speech\\Voices",L"DefaultTokenId",first);
    /* Wine GetDefaultTokenId currently reads this machine-default fallback. */
    if(SUCCEEDED(hr))hr=reg_string(L"Software\\Microsoft\\Speech\\Voices",L"DefaultDefaultTokenId",first);
done:
    HeapFree(GetProcessHeap(),0,voices);return hr;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,void *reserved) {
    (void)reserved;if(reason==DLL_PROCESS_ATTACH){instance=module;DisableThreadLibraryCalls(module);}return TRUE;
}
