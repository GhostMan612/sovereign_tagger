// ============================================================
// As Above, So Below. As Within, So Without.
// The Future Dictates the Past and the Past is Always Present.
// ============================================================

#include <jni.h>
#include <string>
#include <vector>
#include <android/log.h>

#define TAG "WhistleJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

#if WHISTLE_ARM64_SUPPORTED
#include "needle.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

static void* g_mmap_addr = nullptr;
static size_t g_mmap_len = 0;
static int g_loaded = 0;
#endif

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_sovereigntagger_WhistleBridge_nativeIsSupported(JNIEnv *env, jobject thiz) {
#if WHISTLE_ARM64_SUPPORTED
    return JNI_TRUE;
#else
    return JNI_FALSE;
#endif
}

JNIEXPORT jint JNICALL
Java_com_sovereigntagger_WhistleBridge_nativeLoad(JNIEnv *env, jobject thiz, jstring model_path) {
#if WHISTLE_ARM64_SUPPORTED
    if (model_path == nullptr) return -1;
    const char *path = env->GetStringUTFChars(model_path, nullptr);
    if (!path) return -1;

    if (g_mmap_addr != nullptr) {
        munmap(g_mmap_addr, g_mmap_len);
        g_mmap_addr = nullptr;
        g_mmap_len = 0;
        g_loaded = 0;
    }

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        LOGE("Failed to open model file: %s", path);
        env->ReleaseStringUTFChars(model_path, path);
        return -2;
    }

    struct stat sb;
    if (fstat(fd, &sb) < 0) {
        LOGE("Failed to fstat model file: %s", path);
        close(fd);
        env->ReleaseStringUTFChars(model_path, path);
        return -3;
    }

    g_mmap_len = static_cast<size_t>(sb.st_size);
    g_mmap_addr = mmap(nullptr, g_mmap_len, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);

    if (g_mmap_addr == MAP_FAILED) {
        LOGE("Failed to mmap model file: %s", path);
        g_mmap_addr = nullptr;
        g_mmap_len = 0;
        env->ReleaseStringUTFChars(model_path, path);
        return -4;
    }

    int rc = needle_load(static_cast<const unsigned char*>(g_mmap_addr), static_cast<unsigned long long>(g_mmap_len));
    LOGI("needle_load returned %d for %s (size %zu)", rc, path, g_mmap_len);
    env->ReleaseStringUTFChars(model_path, path);

    if (rc >= 0) {
        g_loaded = 1;
        return 0;
    } else {
        const char* err = needle_last_error();
        LOGE("needle_load failed with error: %s", err ? err : "unknown");
        munmap(g_mmap_addr, g_mmap_len);
        g_mmap_addr = nullptr;
        g_mmap_len = 0;
        g_loaded = 0;
        return rc;
    }
#else
    return -999;
#endif
}

JNIEXPORT jstring JNICALL
Java_com_sovereigntagger_WhistleBridge_nativeTranscribe(
    JNIEnv *env, jobject thiz,
    jfloatArray pcm_floats,
    jstring language,
    jstring keywords,
    jboolean word_timestamps
) {
#if WHISTLE_ARM64_SUPPORTED
    if (!g_loaded) {
        return env->NewStringUTF("{\"error\":\"MODEL_NOT_LOADED\"}");
    }
    if (pcm_floats == nullptr) {
        return env->NewStringUTF("{\"error\":\"NO_PCM_DATA\"}");
    }

    jsize sample_count = env->GetArrayLength(pcm_floats);
    if (sample_count <= 0) {
        return env->NewStringUTF("{\"text\":\"\",\"language\":\"en\",\"ttft_ms\":0.0,\"decode_tps\":0.0}");
    }

    jfloat *samples = env->GetFloatArrayElements(pcm_floats, nullptr);
    if (!samples) {
        return env->NewStringUTF("{\"error\":\"FAILED_TO_GET_FLOATS\"}");
    }

    const char *lang_str = language ? env->GetStringUTFChars(language, nullptr) : nullptr;
    const char *kw_str = keywords ? env->GetStringUTFChars(keywords, nullptr) : nullptr;

    const int capacity = 65536;
    std::vector<char> out_buf(capacity, 0);

    int rc = needle_transcribe(
        samples,
        static_cast<int>(sample_count),
        lang_str,
        kw_str,
        word_timestamps ? 1 : 0,
        out_buf.data(),
        capacity
    );

    if (lang_str) env->ReleaseStringUTFChars(language, lang_str);
    if (kw_str) env->ReleaseStringUTFChars(keywords, kw_str);
    env->ReleaseFloatArrayElements(pcm_floats, samples, JNI_ABORT);

    if (rc < 0) {
        const char *err = needle_last_error();
        std::string err_json = std::string("{\"error\":\"") + (err ? err : "TRANSCRIBE_FAILED") + "\"}";
        return env->NewStringUTF(err_json.c_str());
    }

    return env->NewStringUTF(out_buf.data());
#else
    return env->NewStringUTF("{\"error\":\"UNSUPPORTED_ABI\"}");
#endif
}

JNIEXPORT jstring JNICALL
Java_com_sovereigntagger_WhistleBridge_nativeLastError(JNIEnv *env, jobject thiz) {
#if WHISTLE_ARM64_SUPPORTED
    const char *err = needle_last_error();
    return env->NewStringUTF(err ? err : "");
#else
    return env->NewStringUTF("UNSUPPORTED_ABI");
#endif
}

JNIEXPORT void JNICALL
Java_com_sovereigntagger_WhistleBridge_nativeReset(JNIEnv *env, jobject thiz) {
#if WHISTLE_ARM64_SUPPORTED
    needle_reset();
#endif
}

}
