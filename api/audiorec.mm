#include "audiorec.h"
#include <CoreAudio/AudioHardwareTapping.h>
#include <libproc.h>
#include <AppKit/NSRunningApplication.h>
#include <Foundation/NSError.h>
#include <CoreAudio/CATapDescription.h>
#include <Foundation/Foundation.h>

static OSStatus aur_getDefaultUUIDOfAudioDevice(NSString** outString)
{
    *outString = nullptr;
    AudioObjectID obj = kAudioObjectSystemObject;
    AudioObjectPropertyAddress addr;
    addr.mSelector = kAudioHardwarePropertyDefaultSystemOutputDevice;
    addr.mScope = kAudioObjectPropertyScopeGlobal;
    addr.mElement  = kAudioObjectPropertyElementMain;
    AudioDeviceID defaultID;
    UInt32 defaultIDSize = 0;
    OSStatus s = AudioObjectGetPropertyDataSize(obj, &addr, 0, nullptr, &defaultIDSize);
    if(!s) {
        s = AudioObjectGetPropertyData(obj, &addr, 0, nullptr, &defaultIDSize, &defaultID);
        if(!s)  {
            UInt32 dataSize = 0;
            addr.mSelector = kAudioDevicePropertyDeviceUID;
            s = AudioObjectGetPropertyDataSize(defaultID, &addr, 0, nullptr, &dataSize);
            if(!s){
               CFStringRef *ref = nullptr;
               s = AudioObjectGetPropertyData(defaultID, &addr, 0, nullptr, &dataSize, &ref);
               if(!s){
                *outString = (__bridge NSString*) ref;
              }
            }
        }
    }
  return s;
}

static std::map<pid_t, std::string>* aur_GetBSDProcessList()
{
    std::map<pid_t, std::string>* ret = new std::map<pid_t, std::string>;
    if(!ret) {
        return nullptr;
    }
    int bytes_expected = proc_listpids(PROC_ALL_PIDS, 0, nullptr, 0);
    bytes_expected = bytes_expected * 10/sizeof(pid_t);
    pid_t *pids = new pid_t[bytes_expected];
    int bytes_used = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes_expected);
    int cnt =  bytes_used/sizeof(pid_t);
    for (int i = 0; i < cnt; i++)
    {
        struct proc_bsdinfo proc;
        int st = proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0,
                              &proc, PROC_PIDTBSDINFO_SIZE);
        if (st == PROC_PIDTBSDINFO_SIZE)
        {
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier: pids[i]];

            if(app && [[app localizedName] length] > 0) {
                (*ret)[pids[i]] = std::string([[app localizedName] UTF8String]);
            }
            else {
              (*ret)[pids[i]] = std::string(proc.pbi_name);
            }
        }
    }
    delete[] pids;
    return ret;
}

static OSStatus ioproc(AudioObjectID          objID,
                       const AudioTimeStamp*  inNow,
                       const AudioBufferList* inInputData,
                       const AudioTimeStamp*  inInputTime,
                       AudioBufferList*       outOutputData,
                       const AudioTimeStamp*  outOutputTime,
                       void*                  inClientData) noexcept
 {
    aur_rec_t *p = (aur_rec_t*) inClientData;
    if(p && p->callback) {
      p->callback(objID, inNow, inInputData, inInputTime,
                  outOutputData, outOutputTime, p->userData);
    }
    return kAudioHardwareNoError;;
}

static void aur_getAudioPidsInternal(std::map<std::string, pid_t> *p1,
                                     std::map<pid_t,std::string> *p2)
{
    std::map<pid_t, std::string>* allPids = aur_GetBSDProcessList();

    if(!allPids) {
        return;
    }

    if(p1) {
      p1->clear();
    }

    if(p2) {
      p2->clear();
    }

    AudioObjectID obj = kAudioObjectSystemObject;
    AudioObjectPropertyAddress addr;
    addr.mSelector = kAudioHardwarePropertyProcessObjectList;
    addr.mScope = kAudioObjectPropertyScopeGlobal;
    addr.mElement  = kAudioObjectPropertyElementMain;
    UInt32 dataSize = 0;
    
    OSStatus s = AudioObjectGetPropertyDataSize(obj, &addr, 0, nullptr, &dataSize);
    
    if(s != kAudioHardwareNoError) {
        delete allPids;
        return;
    }
    
    int cnt = dataSize/sizeof(AudioObjectID);
    UInt32 *p = new UInt32[cnt];
    
    s = AudioObjectGetPropertyData(obj, &addr, 0, nullptr, &dataSize, p);
    
    if(s == kAudioHardwareNoError) {
      addr.mSelector = kAudioProcessPropertyPID;
      for(int i=0; i<cnt;i++)
      {
        pid_t pid = -1;
        s = AudioObjectGetPropertyDataSize(p[i], &addr, 0, nullptr, &dataSize);
        if(s == kAudioHardwareNoError) {
           s = AudioObjectGetPropertyData(p[i], &addr, 0, nullptr, &dataSize, &pid);
           if(s == kAudioHardwareNoError) {
              auto elem = allPids->find(pid);
              if(elem != allPids->end()) {
                if(p1) {
                  (*p1)[elem->second] = pid;
                }
                else if(p2)
                {
                  (*p2)[pid] = elem->second;
                }
              }
           }
        }
      }
    }
    delete allPids;
    delete[] p;
}

void aur_getAudioPidsOrderedByName(std::map<std::string, pid_t> &pids)
{
  aur_getAudioPidsInternal(&pids, nullptr);
}

void aur_getAudioNamesOrderedByPid(std::map<pid_t,std::string> &pids)
{
  aur_getAudioPidsInternal(nullptr, &pids);
}

bool aur_init(pid_t          in_pid,
              aur_callback_t in_callbackRec,
              aur_rec_t**    out_handle)
{
  if(!in_callbackRec) {
      return false;
  }

  *out_handle = nullptr;
  aur_rec_t *c = new aur_rec_t;
  
  if(!c) {
      return false;
  }
  
  c->userData = nullptr;
  c->pid = in_pid;
  c->callback = in_callbackRec;

  AudioObjectID obj = kAudioObjectSystemObject;
  AudioObjectPropertyAddress addr;
  addr.mSelector = kAudioHardwarePropertyTranslatePIDToProcessObject;
  addr.mScope = kAudioObjectPropertyScopeGlobal;
  addr.mElement  = kAudioObjectPropertyElementMain;
  UInt32 dataSize = 0;
  OSStatus ret = AudioObjectGetPropertyDataSize(obj, &addr, 0, nullptr, &dataSize);

  if(ret!=kAudioHardwareNoError)
  {
      delete c;
      return false;
  }

  ret = AudioObjectGetPropertyData(obj, &addr, sizeof(c->pid), &c->pid, &dataSize, &c->pidObj);
 
  if(ret!=kAudioHardwareNoError)
  {
      delete c;
      return false;
  }

  NSProcessInfo *processInfo = [NSProcessInfo processInfo];
  int processID = [processInfo processIdentifier];
  NSUUID* tapUUID = [NSUUID UUID];

  CATapDescription *desc = [[CATapDescription alloc]
                               initStereoMixdownOfProcesses:
                                 [NSArray arrayWithObject:
                                    [NSNumber numberWithInt: c->pidObj]]];

  desc.name = [NSString stringWithFormat: @"audiorec-tap-%d", processID];
  desc.UUID = tapUUID;
  desc.privateTap = true;
  desc.muteBehavior = CATapUnmuted;
  desc.exclusive = false;
  desc.mixdown = true;

  c->tapID = kAudioObjectUnknown;
  ret = AudioHardwareCreateProcessTap(desc, &c->tapID);

  if(ret!=kAudioHardwareNoError)
  {
    delete c;
    [desc release];
    return false;
  }

  NSString *deviceName = [NSString stringWithFormat: @"audiorec-agreggated-%d", processID];
  NSNumber *isPrivateKey = [NSNumber numberWithBool: true];
  NSNumber *isStackedKey = [NSNumber numberWithBool: false];
  NSNumber *tapAutoStartKey = [NSNumber numberWithBool: true];

  NSArray* tapConf = [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                      [NSNumber numberWithBool:true],
                           [NSString stringWithUTF8String: kAudioSubTapDriftCompensationKey],
                      tapUUID.UUIDString, 
                          [NSString stringWithUTF8String: kAudioSubTapUIDKey],
                      nil]];

  NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                         deviceName, [NSString stringWithUTF8String:kAudioAggregateDeviceNameKey],
                         [[NSUUID UUID] UUIDString], [NSString stringWithUTF8String:kAudioAggregateDeviceUIDKey],
                         isPrivateKey, [NSString stringWithUTF8String: kAudioAggregateDeviceIsPrivateKey],
                         tapConf, [NSString stringWithUTF8String:kAudioAggregateDeviceTapListKey],
                         nil];

  CFDictionaryRef dictBridge = (__bridge CFDictionaryRef) dict;
  ret = AudioHardwareCreateAggregateDevice(dictBridge, &c->aggregatedID);
  
  if(ret!=kAudioHardwareNoError)
  {
    AudioHardwareDestroyProcessTap(c->tapID);
    delete c;
    [desc release];
    return false;
  }


  ret = AudioDeviceCreateIOProcID(c->aggregatedID, ioproc, c, &c->ioproc);

  if(ret!=kAudioHardwareNoError)
  {
    AudioHardwareDestroyAggregateDevice(c->aggregatedID);
    AudioHardwareDestroyProcessTap(c->tapID);
    delete c;
    [desc release];
    return false;
  }

  [desc release];
  *out_handle = c;
  return true;
}

bool aur_start(aur_rec_t* c,
               void*      in_userData)
{
  bool ret = false;
  if(c) {
    c->userData = in_userData;
    ret = AudioDeviceStart(c->aggregatedID, c->ioproc);
    
    if(ret==kAudioHardwareNoError)
    {
      ret = true;
    }
  }
  return ret;
}

void aur_stop(aur_rec_t* c)
{
  if(c) {
    AudioDeviceStop(c->aggregatedID, c->ioproc);
  }
}

void aur_deinit(aur_rec_t* c)
{
  if(c) {
    AudioDeviceDestroyIOProcID(c->aggregatedID, c->ioproc);
    AudioHardwareDestroyAggregateDevice(c->aggregatedID);
    AudioHardwareDestroyProcessTap(c->tapID);
    delete c;
  }
}
