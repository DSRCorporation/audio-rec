#include <CoreFoundation/CoreFoundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <ApplicationServices/ApplicationServices.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <paths.h>
#include <libproc.h>
#include <map>
#include <string>
#include <CoreServices/CoreServices.h>
#include <CoreAudio/CoreAudio.h>
#include "../api/audiorec.h"
#include <AVFAudio/AVFAudio.h>

#define VERSION "1.01"

typedef struct {
    AVAudioFile *fileRef;
    AVAudioFormat *format;
} user_data_t;

enum class StreamDirection : UInt32 {
    output,
    input
};

constexpr AudioObjectPropertyAddress PropertyAddress(AudioObjectPropertySelector selector,
                                                     AudioObjectPropertyScope scope = kAudioObjectPropertyScopeGlobal,
                                                     AudioObjectPropertyElement element = kAudioObjectPropertyElementMain) noexcept {
    return {selector, scope, element};
}

void catalogDeviceStreams(AudioObjectID did,
                          std::shared_ptr<std::vector<AudioStreamBasicDescription>> &inputStreamList,
                          std::shared_ptr<std::vector<AudioStreamBasicDescription>> &outputStreamList)
{
    inputStreamList->clear();
    outputStreamList->clear();

    if (did == kAudioObjectUnknown) {
        return;
    }

    UInt32 size = 0;
    AudioObjectPropertyAddress address = PropertyAddress(kAudioDevicePropertyStreams);
    OSStatus error = AudioObjectGetPropertyDataSize(did, &address, 0, nullptr, &size);
    auto streamCount = size / sizeof(AudioObjectID);
    if (error != kAudioHardwareNoError || streamCount == 0) {
        return;
    }
    std::vector<AudioObjectID> streamList(streamCount);
    error = AudioObjectGetPropertyData(did, &address, 0, nullptr, &size, streamList.data());
    if (error != kAudioHardwareNoError) {
        return;
    }

    streamList.resize(size / sizeof(AudioObjectID));
    for (auto streamID : streamList) {
        address = PropertyAddress(kAudioStreamPropertyVirtualFormat);
        AudioStreamBasicDescription format;
        size = sizeof(AudioStreamBasicDescription);
        memset(&format, 0, size);
        error = AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &format);
        if (error == kAudioHardwareNoError) {
            address = PropertyAddress(kAudioStreamPropertyDirection);
            StreamDirection direction = StreamDirection::output;
            size = sizeof(UInt32);
            AudioObjectGetPropertyData(streamID, &address, 0, nullptr, &size, &direction);
            if (direction == StreamDirection::output) {
                outputStreamList->push_back(format);
            }
            else {
                inputStreamList->push_back(format);
            }
        }
    }
}

bool makeRecordingFile(pid_t pid, char* c_path, AudioStreamBasicDescription* format,AVAudioFormat** outFormat, AVAudioFile** file)
{
    *outFormat = [[AVAudioFormat alloc] initWithStreamDescription:format];

    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                      [NSNumber numberWithInt:format->mFormatID],  AVFormatIDKey,
                      [NSNumber numberWithFloat: format->mSampleRate], AVSampleRateKey,
                      [NSNumber numberWithInt:format->mChannelsPerFrame],  AVNumberOfChannelsKey,
                      nil];

    NSDate *date = [NSDate date];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle]; 
    [dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
    NSString *dateString = [dateFormatter stringFromDate: date];
    dateString = [dateString stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    dateString = [dateString stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    dateString = [dateString stringByReplacingOccurrencesOfString:@"+" withString:@""];
    [dateFormatter release];
    auto* path = [NSString stringWithFormat: @"%s/pid-%d-recording-%@.wav", c_path, pid, dateString];
    auto* url = [NSURL fileURLWithPath: path];

    *file = nil;
    NSError* error = nil;
    *file = [[AVAudioFile alloc] initForWriting: url
                                             settings: settings
                                         commonFormat: AVAudioPCMFormatFloat32
                                          interleaved: (*outFormat).interleaved
                                                error: &error ];
    if(error != nil)
    {
      if(*outFormat) {
        [*outFormat release];
      }
      if(*file) {
        [*file release];
      }
      return false;
    }
    return true;
}

void audio_callback(AudioObjectID          objID,
                    const AudioTimeStamp*  inNow,
                    const AudioBufferList* inInputData,
                    const AudioTimeStamp*  inInputTime,
                          AudioBufferList* outOutputData,
                    const AudioTimeStamp*  inOutputTime,
                    void*                  inUserData) noexcept
{
  user_data_t *u = (user_data_t*) inUserData;
  AVAudioPCMBuffer* buffer = [[ AVAudioPCMBuffer alloc] initWithPCMFormat: u->format
                                                         bufferListNoCopy: inInputData
                                                         deallocator: nil];
  [u->fileRef writeFromBuffer: buffer error:nil];
  [buffer release];
}

int record_audio(int pid, char* path)
{
    std::map<pid_t, std::string> audioPids;
    aur_getAudioNamesOrderedByPid(audioPids);
    auto ret = audioPids.find(pid);
    if(ret == audioPids.end()) {
      printf("You need to launch Safari!\n");
      return -1;
    }

    aur_rec_t *h = nullptr;
    bool res = aur_init(ret->first, audio_callback, &h);
    if(!res) {
      printf("Can't initialize audio recording for pid %d!\n", pid);
      return -1;
    }

    std::shared_ptr<std::vector<AudioStreamBasicDescription>> inputStreamList = std::make_shared<std::vector<AudioStreamBasicDescription>>();
    std::shared_ptr<std::vector<AudioStreamBasicDescription>> outputStreamList = std::make_shared<std::vector<AudioStreamBasicDescription>>();

    catalogDeviceStreams(h->aggregatedID, inputStreamList, outputStreamList);

    user_data_t params;
    params.fileRef = nil;
    params.format = nil;
    res  = makeRecordingFile(pid, path, &inputStreamList->at(0), &params.format, &params.fileRef);

    if(!res) {
      printf("creation of recording file failed!");
      aur_deinit(h);
      return -1;
    }

    res = aur_start(h, &params);

    if(!res) {
      printf("failed to start audio capturing!\n");
      aur_deinit(h);
      return -1;
    }

    printf("Audio recording started, press enter to stop...\n");
    int c = 0;
    while (read(STDIN_FILENO, &c, 1) == 1 && c != '\n');
    aur_stop(h);
    [params.fileRef release];
    [params.format release];
    aur_deinit(h);
    return 0;
}

void show_usage()
{
  printf("Audio Recorder v%s: copyright DSR corporation, 2024. \n", VERSION);
  printf("Usage: audio_rec [command]\n");
  printf("Commands:\n");
  printf("    -l - to show list of process pids to record audio from.\n");
  printf("    -r [pid] [filepath] - to record an audio from process with pid\n");
  printf("                          to folder specified by filepath.\n");
  printf("Examples:\n");
  printf("   audio_rec -l\n");
  printf("   audio_rec -p 1980 ~/recordings\n");
}

int main(int argc, char *argv[])
{
    int ret = 0;
    if(argc == 2 && strncmp(argv[1], "-l", 2)==0) {
      std::map<std::string, pid_t> audioPids;
      std::map<std::string, pid_t>::iterator it;
      aur_getAudioPidsOrderedByName(audioPids);
      for (it = audioPids.begin(); it != audioPids.end(); it++)
      {
          printf("%d %s\n", (int)it->second, (char*)it->first.c_str());
      }
    }
    else if(argc == 4 && strncmp(argv[1], "-p", 2) == 0) {
      pid_t pid = atoi(argv[2]);
      ret = record_audio(pid, argv[3]);
    }
    else {
       show_usage();
    }
    return ret;
}
