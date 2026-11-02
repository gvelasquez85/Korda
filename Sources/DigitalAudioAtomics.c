#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
typedef struct { _Atomic float gain; _Atomic unsigned long frames; _Atomic int fault; unsigned channels; AudioConverterRef converter; float *fifo; unsigned count,cursor,capacity; } KordaDSP;
void *korda_dsp_create(unsigned channels) { if(channels<1||channels>2)return NULL; KordaDSP *s=calloc(1,sizeof(*s)); if(s){atomic_init(&s->gain,0.5f);atomic_init(&s->frames,0);atomic_init(&s->fault,0);s->channels=channels;if(!atomic_is_lock_free(&s->gain)||!atomic_is_lock_free(&s->frames)||!atomic_is_lock_free(&s->fault)){free(s);return NULL;}} return s; }
void korda_dsp_destroy(void *p){KordaDSP *s=p;if(s->converter)AudioConverterDispose(s->converter);free(s->fifo);free(p);}
static OSStatus provide(AudioConverterRef converter,UInt32 *packets,AudioBufferList *data,AudioStreamPacketDescription **descriptions,void *context){
 KordaDSP *s=context;unsigned available=s->count-s->cursor;
 if(!available){*packets=0;return 1;}
 unsigned n=*packets<available?*packets:available;
 data->mNumberBuffers=1;data->mBuffers[0].mNumberChannels=s->channels;
 data->mBuffers[0].mData=s->fifo+s->cursor*s->channels;
 data->mBuffers[0].mDataByteSize=n*s->channels*sizeof(float);
 *packets=n;s->cursor+=n;return noErr;
}
void *korda_dsp_create_rates(unsigned channels,double inputRate,double outputRate){
 KordaDSP *s=korda_dsp_create(channels);if(!s)return NULL;
 if(!isfinite(inputRate)||!isfinite(outputRate)||inputRate<8000||outputRate<8000||inputRate>192000||outputRate>192000){korda_dsp_destroy(s);return NULL;}
 if(inputRate==outputRate)return s;
 s->capacity=65536;s->fifo=calloc(s->capacity*channels,sizeof(float));
 if(!s->fifo){korda_dsp_destroy(s);return NULL;}
 AudioStreamBasicDescription in={.mSampleRate=inputRate,.mFormatID=kAudioFormatLinearPCM,.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,.mBytesPerPacket=4*channels,.mFramesPerPacket=1,.mBytesPerFrame=4*channels,.mChannelsPerFrame=channels,.mBitsPerChannel=32};
 AudioStreamBasicDescription out=in;out.mSampleRate=outputRate;
 if(AudioConverterNew(&in,&out,&s->converter)){korda_dsp_destroy(s);return NULL;}
 UInt32 quality=kAudioConverterQuality_High,prime=kConverterPrimeMethod_None;
 if(AudioConverterSetProperty(s->converter,kAudioConverterSampleRateConverterQuality,sizeof(quality),&quality)||AudioConverterSetProperty(s->converter,kAudioConverterPrimeMethod,sizeof(prime),&prime)){korda_dsp_destroy(s);return NULL;}
 // Exercise conversion before realtime IO, retaining converter state and allocations.
 float *warm=calloc(8192*channels,sizeof(float));if(!warm){korda_dsp_destroy(s);return NULL;}
 s->count=32768;s->cursor=0;UInt32 frames=8192;
 AudioBufferList output={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=channels,.mDataByteSize=8192*channels*4,.mData=warm}}};
 OSStatus result=AudioConverterFillComplexBuffer(s->converter,provide,s,&frames,&output,NULL);
 free(warm);s->count=0;s->cursor=0;
 if(result && result!=1){korda_dsp_destroy(s);return NULL;}
 return s;
}
void korda_dsp_gain(void *p,float g){atomic_store_explicit(&((KordaDSP*)p)->gain,isfinite(g)?fmaxf(0,fminf(1,g)):0,memory_order_relaxed);}
unsigned long korda_dsp_frames(void *p){return atomic_load_explicit(&((KordaDSP*)p)->frames,memory_order_relaxed);}
int korda_dsp_fault(void *p){return atomic_load_explicit(&((KordaDSP*)p)->fault,memory_order_relaxed);}
OSStatus korda_audio_callback(AudioObjectID device,const AudioTimeStamp *now,const AudioBufferList *input,const AudioTimeStamp *inputTime,AudioBufferList *output,const AudioTimeStamp *outputTime,void *context){
 KordaDSP *s=context;
 if(!output) return noErr;
 for(unsigned i=0;i<output->mNumberBuffers;i++) if(output->mBuffers[i].mData) memset(output->mBuffers[i].mData,0,output->mBuffers[i].mDataByteSize);
 if(!input||input->mNumberBuffers!=1||output->mNumberBuffers!=1) { atomic_store(&s->fault,1);return noErr; }
 const AudioBuffer *in=&input->mBuffers[0];AudioBuffer *out=&output->mBuffers[0];
 if(!in->mData||!out->mData||in->mNumberChannels!=s->channels||out->mNumberChannels!=s->channels||in->mDataByteSize%(sizeof(float)*s->channels)||(!s->converter&&in->mDataByteSize!=out->mDataByteSize)||out->mDataByteSize%(sizeof(float)*s->channels)){atomic_store(&s->fault,1);return noErr;}
 float g=atomic_load_explicit(&s->gain,memory_order_relaxed);const float *src=in->mData;float *dst=out->mData;
 if(s->converter){
  unsigned inFrames=in->mDataByteSize/(4*s->channels);
  if(inFrames>s->capacity-s->count){atomic_store(&s->fault,1);return noErr;}
  for(unsigned i=0;i<inFrames*s->channels;i++)s->fifo[s->count*s->channels+i]=isfinite(src[i])?src[i]:0;
  s->count+=inFrames;s->cursor=0;
  UInt32 wanted=out->mDataByteSize/(4*s->channels),produced=wanted;
  AudioBufferList target=*output;
  OSStatus result=AudioConverterFillComplexBuffer(s->converter,provide,s,&produced,&target,NULL);
  unsigned remain=s->count-s->cursor;
  memmove(s->fifo,s->fifo+s->cursor*s->channels,remain*s->channels*sizeof(float));s->count=remain;s->cursor=0;
  if(produced>wanted || (result && result!=1)){memset(out->mData,0,out->mDataByteSize);atomic_store(&s->fault,1);return noErr;}
  for(unsigned i=0;i<produced*s->channels;i++)dst[i]=isfinite(dst[i])?dst[i]*g:0;
  atomic_fetch_add_explicit(&s->frames,produced,memory_order_relaxed);
  return noErr;
 }
 for(unsigned i=0;i<out->mDataByteSize/sizeof(float);i++) dst[i]=isfinite(src[i])?src[i]*g:0;
 atomic_fetch_add_explicit(&s->frames,out->mDataByteSize/(sizeof(float)*s->channels),memory_order_relaxed);
 return noErr;
}
