import os
import urllib.request
import zipfile
import shutil

def install_acrcloud_native():
    url = "https://github.com/acrcloud/ACRCloudUniversalSDK/archive/refs/heads/master.zip"
    zip_path = "acr_sdk.zip"
    
    print("[1/5] Downloading ACRCloud Native SDK (~50MB)...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response, open(zip_path, 'wb') as out_file:
        shutil.copyfileobj(response, out_file)
        
    print("[2/5] Extracting SDK...")
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall("acr_temp")
        
    base_libs = "acr_temp/ACRCloudUniversalSDK-master/libs"
    
    app_libs = os.path.join("android", "app", "libs")
    app_jni = os.path.join("android", "app", "src", "main", "jniLibs")
    
    os.makedirs(app_libs, exist_ok=True)
    os.makedirs(app_jni, exist_ok=True)
    
    print("[3/5] Linking Java Wrapper (.jar)...")
    for file in os.listdir(base_libs):
        if file.endswith(".jar"):
            shutil.copy(os.path.join(base_libs, file), app_libs)
            print(f"      -> {file}")
            
    print("[4/5] Linking C++ JNI Binaries (.so)...")
    for arch in ["arm64-v8a", "armeabi-v7a", "x86", "x86_64"]:
        src_arch = os.path.join(base_libs, arch)
        if os.path.exists(src_arch):
            dst_arch = os.path.join(app_jni, arch)
            if os.path.exists(dst_arch):
                shutil.rmtree(dst_arch)
            shutil.copytree(src_arch, dst_arch)
            print(f"      -> {arch} linked.")
            
    print("[5/5] Cleaning up...")
    os.remove(zip_path)
    shutil.rmtree("acr_temp")
    
    print("\nSUCCESS: Path A Native Integration Complete. JNI binaries are in position.")

if __name__ == "__main__":
    install_acrcloud_native()