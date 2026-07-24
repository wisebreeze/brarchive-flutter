#ifndef RUNNER_FILE_PICKER_PLUGIN_H_
#define RUNNER_FILE_PICKER_PLUGIN_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_message_codec.h>

#include <memory>
#include <string>

// Registers the native file picker method channel with the Flutter engine.
void FilePickerPluginRegisterWithEngine(flutter::FlutterEngine* engine);

#endif  // RUNNER_FILE_PICKER_PLUGIN_H_
