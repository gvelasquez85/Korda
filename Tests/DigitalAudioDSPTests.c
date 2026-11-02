#include <CoreAudio/CoreAudio.h>
#include <assert.h>
#include <math.h>
void *korda_dsp_create(unsigned);
void *korda_dsp_create_rates(unsigned,double,double);
unsigned long korda_dsp_frames(void*);
void korda_dsp_destroy(void*);
void korda_dsp_gain(void*,float);
int korda_dsp_fault(void*);
OSStatus korda_audio_callback(AudioObjectID,const AudioTimeStamp*,const AudioBufferList*,const AudioTimeStamp*,AudioBufferList*,const AudioTimeStamp*,void*);
int main(void){
 void *s=korda_dsp_create(2);assert(s);
 float in[]={1,-1,NAN,0.5f},out[4]={0};
 AudioBufferList input={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=2,.mDataByteSize=sizeof(in),.mData=in}}};
 AudioBufferList output={.mNumberBuffers=1,.mBuffers={{.mNumberChannels=2,.mDataByteSize=sizeof(out),.mData=out}}};
 korda_dsp_gain(s,0.5f);korda_audio_callback(0,0,&input,0,&output,0,s);
 assert(out[0]==0.5f&&out[1]==-0.5f&&out[2]==0&&out[3]==0.25f);
 korda_dsp_gain(s,0);korda_audio_callback(0,0,&input,0,&output,0,s);assert(out[0]==0&&out[1]==0);
 korda_dsp_gain(s,4);korda_audio_callback(0,0,&input,0,&output,0,s);assert(out[0]==1);
 korda_dsp_gain(s,NAN);korda_audio_callback(0,0,&input,0,&output,0,s);assert(out[0]==0);
 input.mBuffers[0].mDataByteSize=3;korda_audio_callback(0,0,&input,0,&output,0,s);assert(korda_dsp_fault(s)&&out[0]==0);
 korda_audio_callback(0,0,0,0,&output,0,s);assert(out[0]==0);
 korda_dsp_destroy(s);
 s=korda_dsp_create_rates(2,44100,48000);assert(s);korda_dsp_gain(s,1);
 float sine[882],converted[960];unsigned crossings=0;float previous=0;
 input.mBuffers[0].mData=sine;input.mBuffers[0].mDataByteSize=sizeof(sine);
 output.mBuffers[0].mData=converted;output.mBuffers[0].mDataByteSize=sizeof(converted);
 for(unsigned block=0;block<200;block++){
  for(unsigned f=0;f<441;f++)sine[f*2]=sine[f*2+1]=sinf(2*M_PI*1000*(block*441+f)/44100.0);
  korda_audio_callback(0,0,&input,0,&output,0,s);assert(!korda_dsp_fault(s));
  if(block>=100)for(unsigned f=0;f<480;f++){float sample=converted[f*2];assert(isfinite(sample));if(previous<=0&&sample>0)crossings++;previous=sample;}
 }
 assert(crossings>=995&&crossings<=1005);
 assert(korda_dsp_frames(s)>=95000&&korda_dsp_frames(s)<=96000);
 korda_dsp_gain(s,0);korda_audio_callback(0,0,&input,0,&output,0,s);
 for(unsigned i=0;i<960;i++)assert(converted[i]==0);
 korda_dsp_destroy(s);return 0;
}
