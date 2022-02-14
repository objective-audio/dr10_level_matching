//
//  AppDelegate.m
//

#import "AppDelegate.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <audio/yas_audio_umbrella.h>
#include <cpp_utils/yas_cf_utils.h>
#include <cpp_utils/yas_fast_each.h>
#include <cpp_utils/yas_url.h>

#include <iostream>

using namespace yas;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (IBAction)openDocument:(id)sender {
    auto *openPanel = [NSOpenPanel openPanel];
    openPanel.message = @"通常録音のファイルを選択";
    openPanel.canChooseDirectories = NO;
    openPanel.canChooseFiles = YES;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedContentTypes = @[UTTypeAudio];

    if ([openPanel runModal] != NSModalResponseOK) {
        return;
    }

    auto const src_path = to_string((__bridge CFStringRef)openPanel.URL.absoluteString);
    url const src_file_url{src_path};

    openPanel = [NSOpenPanel openPanel];
    openPanel.message = @"デュアル録音のファイルを選択";
    openPanel.canChooseDirectories = NO;
    openPanel.canChooseFiles = YES;
    openPanel.allowsMultipleSelection = NO;
    openPanel.allowedContentTypes = @[UTTypeAudio];

    if ([openPanel runModal] != NSModalResponseOK) {
        return;
    }

    auto const src_path_d = to_string((__bridge CFStringRef)openPanel.URL.absoluteString);
    url const src_file_url_d{src_path_d};

    auto const dst_file_name = src_file_url.deleting_path_extension().last_path_component() + "_F.wav";

    auto *const savePanel = [NSSavePanel savePanel];
    savePanel.message = @"書き出し先を指定";
    savePanel.canCreateDirectories = YES;
    savePanel.nameFieldStringValue = (__bridge NSString *)to_cf_object(dst_file_name);

    if ([savePanel runModal] != NSModalResponseOK) {
        return;
    }

    auto const dst_path = to_string((__bridge CFStringRef)savePanel.URL.absoluteString);
    url const dst_file_url{dst_path};

    auto const src_file_result = audio::file::make_opened({.file_url = src_file_url});
    if (src_file_result.is_error()) {
        std::cout << src_file_result.error() << std::endl;
        return;
    }

    auto const src_file_d_result = audio::file::make_opened({.file_url = src_file_url_d});
    if (src_file_d_result.is_error()) {
        std::cout << src_file_d_result.error() << std::endl;
        return;
    }

    auto const src_file = src_file_result.value();
    auto const src_file_d = src_file_d_result.value();

    if (src_file->processing_format() != src_file_d->processing_format()) {
        std::cout << "diff format" << std::endl;
        return;
    }

    auto const &src_format = src_file->processing_format();
    audio::format const dst_format{
        {.sample_rate = src_format.sample_rate(), .channel_count = src_format.channel_count()}};

    auto const dst_file_result = audio::file::make_created(
        {.file_url = dst_file_url,
         .settings = audio::wave_file_settings(dst_format.sample_rate(), dst_format.channel_count(), 32)});
    if (dst_file_result.is_error()) {
        std::cout << dst_file_result.error() << std::endl;
        return;
    }

    auto const dst_file = dst_file_result.value();

    auto const sample_rate = static_cast<uint32_t>(src_format.sample_rate());

    audio::pcm_buffer src_buffer{src_format, sample_rate};
    audio::pcm_buffer src_buffer_d{src_format, sample_rate};
    audio::pcm_buffer dst_buffer{dst_format, sample_rate};

    auto const rate_d = audio::math::linear_from_decibel(12.0f);

    while (true) {
        if (auto const result = src_file->read_into_buffer(src_buffer); !result) {
            std::cout << "read failed : " << result.error() << std::endl;
        }

        if (auto const result = src_file_d->read_into_buffer(src_buffer_d); !result) {
            std::cout << "read failed : " << result.error() << std::endl;
        }

        if (src_buffer.frame_length() != src_buffer_d.frame_length()) {
            std::cout << "diff frame_length" << std::endl;
            break;
        }

        if (src_buffer.frame_length() == 0 || src_buffer_d.frame_length() == 0) {
            std::cout << "end of file" << std::endl;
            break;
        }

        dst_buffer.set_frame_length(src_buffer.frame_length());

        auto ch_each = make_fast_each(src_format.channel_count());
        while (yas_each_next(ch_each)) {
            auto const &ch_idx = yas_each_index(ch_each);

            auto const *const src_ptr = src_buffer.data_ptr_at_index<float>(ch_idx);
            auto const *const src_d_ptr = src_buffer_d.data_ptr_at_index<float>(ch_idx);
            auto *const dst_ptr = dst_buffer.data_ptr_at_index<float>(ch_idx);

            auto frame_each = make_fast_each(src_buffer.frame_length());
            while (yas_each_next(frame_each)) {
                auto const &frame_idx = yas_each_index(frame_each);
                float const src_value = src_ptr[frame_idx];
                float const src_value_d = src_d_ptr[frame_idx] * rate_d;

                if (std::abs(src_value_d) < 0.125) {
                    dst_ptr[frame_idx] = src_value;
                } else {
                    dst_ptr[frame_idx] = src_value_d;
                }
            }
        }

        dst_file->write_from_buffer(dst_buffer);
    }
}

@end
