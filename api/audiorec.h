#ifndef __audiorec__included__
#define __audiorec__included__

#include <CoreFoundation/CoreFoundation.h>
#include <CoreAudio/CoreAudio.h>
#include <map>

typedef void (*aur_callback_t)(
                             AudioObjectID          objID,
                             const AudioTimeStamp*  inNow,
                             const AudioBufferList* inInputData,
                             const AudioTimeStamp*  inInputTime,
                                   AudioBufferList* outOutputData,
                             const AudioTimeStamp*  inOutputTime,
                             void*                  inUserData) noexcept;

typedef struct
{
  AudioDeviceIOProcID ioproc;
  AudioObjectID pidObj;
  pid_t pid;
  aur_callback_t callback;
  void* userData;
  AudioObjectID tapID;
  AudioObjectID aggregatedID;
} aur_rec_t;

/**
 * @brief aur_getAudioPidsOrderedByName() function gets pids of all existent
 *        client processes currently connected to audio system.
 * @param pids - map which contains pids. The key of the map represents
 *               user friendly name of process which can be used by GUI
 *               to show it to user.
 */

void aur_getAudioPidsOrderedByName(std::map<std::string, pid_t> &pids);

/**
 * @brief aur_getAudioNamesOrderedByPid() function gets pids of all existent
 *        client processes currently connected to audio system.
 * @param pids - map which contains pids. The key of the map is pid,
 *               value is a user friendly name of process which can be
 *               used by GUI to show it to user.
 */

void aur_getAudioNamesOrderedByPid(std::map<pid_t,std::string> &pids);

/**
 * @brief aur_init() function initializes a capturing audio session from
 *                 a process defined by in_pid parameter.
 * @param in_pid - pid of the process to capture audio from.
 * @param in_callbackRec - callback for the audio data captured from
 *                         a process defined by in_pid parameter.
 * @param out_handle - handle of the initialized capturing session.
 * @return true if audio capturing session was initialized successfully,
 *              otherwise returns false.
 */

bool aur_init(pid_t          in_pid,
              aur_callback_t in_callbackRec,
              aur_rec_t**    out_handle);

/**
 * @brief aur_start() starts capturing the audio for the process defined
 *        by pid parameter which was passed to aur_init() function before.
 *        After that call, callback function is called in the context of 
 *        core audio thread. 
 * @param in_handle - handle of the initialized capturing session.
 * @param in_userData - pointer to an user data which can be passed callback for the audio data captured from
 *                         a process defined by in_pid parameter.
 * @param out_handle - handle of the initialized capturing session.
 * @return true if audio capturing was started successfully,
 *              otherwise returns false.
 */

bool aur_start(aur_rec_t* in_handle,
               void* in_userData);

/**
 * @brief aur_stop() stops capturing the audio. Note that after that call
 *                   callback function with audio  data won't be called
 *                   anymore.
 * @param in_handle - handle of the started recorded session.
 */

void aur_stop(aur_rec_t* in_handle);

/**
 * @brief aur_deinit() deinitializes previously initialized recording audio
 *                     session.
 * @param in_handle - handle of the started recorded session.
 */

void aur_deinit(aur_rec_t* in_handle);

#endif
