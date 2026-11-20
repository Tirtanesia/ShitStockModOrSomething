LOG_STEP_IN "- Replacing camera blobs"
BLOBS_LIST="
system/lib64/libenn_wrapper_system.so
system/lib64/libpic_best.arcsoft.so
system/lib64/libarcsoft_dualcam_portraitlighting.so
system/lib64/libdualcam_refocus_gallery_54.so
system/lib64/libdualcam_refocus_gallery_50.so
system/lib64/libhybrid_high_dynamic_range.arcsoft.so
system/lib64/libae_bracket_hdr.arcsoft.so
system/lib64/libface_recognition.arcsoft.so
system/lib64/libDualCamBokehCapture.camera.samsung.so
"
for blob in $BLOBS_LIST
do
    DELETE_FROM_WORK_DIR "system" "$blob" &
done

# shellcheck disable=SC2046
wait $(jobs -p) || exit 1

BLOBS_LIST="
system/lib64/libPortraitDistortionCorrectionCali.arcsoft.so
system/lib64/libMultiFrameProcessing20.camera.samsung.so
system/lib64/libMultiFrameProcessing20Core.camera.samsung.so
system/lib64/libMultiFrameProcessing20Day.camera.samsung.so
system/lib64/libMultiFrameProcessing20Tuning.camera.samsung.so
system/lib64/libMultiFrameProcessing30.camera.samsung.so
system/lib64/libMultiFrameProcessing30.snapwrapper.camera.samsung.so
system/lib64/libMultiFrameProcessing30Tuning.camera.samsung.so
system/lib64/libGeoTrans10.so
system/lib64/vendor.samsung_slsi.hardware.geoTransService@1.0.so
system/lib64/libSwIsp_core.camera.samsung.so
system/lib64/libSwIsp_wrapper_v1.camera.samsung.so
system/lib64/libBestComposition.polarr.so
system/lib64/libFeature.polarr.so
system/lib64/libPolarrSnap.polarr.so
system/lib64/libTracking.polarr.so
system/lib64/libYuv.polarr.so
"
# Polarr: the camera-feature keeps SUPPORT_COMPOSITION_GUIDE and
# AutoBeautyPhotoMaker always builds PolarrCompositionGuideNode, but the source
# firmware ships no Polarr libraries, so the app died with UnsatisfiedLinkError
# (PolarrSmartCrop.useGPU) when photo or video mode started. With
# libFeature.polarr.so present the app takes the v2 API, whose natives these
# stock libraries export, and reads its databases from system/saiv.
for blob in $BLOBS_LIST
do
    ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0" &
done

if [[ "$TARGET_CODENAME" == "c1s" || "$TARGET_CODENAME" == "c2s" ]]; then
    BLOBS_LIST="
    system/lib64/libofi_seva.so
    system/lib64/libofi_klm.so
    system/lib64/libofi_plugin.so
    system/lib64/libofi_rt_framework_user.so
    system/lib64/libofi_service_interface.so
    system/lib64/libofi_gc.so
    system/lib64/vendor.samsung_slsi.hardware.ofi@2.0.so
    system/lib64/vendor.samsung_slsi.hardware.ofi@2.1.so
    "
    for blob in $BLOBS_LIST
    do
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0" &
    done
fi

# shellcheck disable=SC2046
wait $(jobs -p) || exit 1

LOG_STEP_OUT

# Once the Exynos HAL receives the Samsung Camera parameter string it selects
# SUPER_NIGHT_HANDHELD by itself, and the camera app dlopen()s the MPI solution.
# The source firmware ships it in /vendor with /vendor-relative dependencies;
# the target build loads /system/lib64/{libLocalTM_pcc,libMultiFrameProcessing30,
# libSwIsp_wrapper_v1}, which matches this platform's system closure.
LOG_STEP_IN "- Restoring the target Super Night MPI solution"
# A Samsung Camera (priv-app) carrega estas libs de /system/lib64 sem entrada
# em public.libraries; validado no y2s com as versões do G986B (02/11/2026).
for blob in \
    "system/lib64/libAIQSolution_MPI.camera.samsung.so" \
    "system/lib64/libLocalTM_pcc.camera.samsung.so"
do
    if [ -f "$FW_DIR/$TARGET_FIRMWARE_PATH/system/$blob" ]; then
        ADD_TO_WORK_DIR "$TARGET_FIRMWARE" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0"
    fi
done
LOG_STEP_OUT

LOG_STEP_IN "- Exposing ArcSoft Object Capture to updated DressRoom builds"
ARCSOFT_PUBLIC_LIBS="$WORK_DIR/system/system/etc/public.libraries-arcsoft.txt"
if [ ! -f "$ARCSOFT_PUBLIC_LIBS" ]; then
    ABORT "Missing ArcSoft public native-library list"
fi
for ARCSOFT_PUBLIC_LIB in \
    "libobjectcapture.arcsoft.so" \
    "libobjectcapture_jni.arcsoft.so"
do
    grep -qxF "$ARCSOFT_PUBLIC_LIB" "$ARCSOFT_PUBLIC_LIBS" || \
        printf '%s\n' "$ARCSOFT_PUBLIC_LIB" >> "$ARCSOFT_PUBLIC_LIBS"
done
unset ARCSOFT_PUBLIC_LIB ARCSOFT_PUBLIC_LIBS
LOG_STEP_OUT

LOG_STEP_IN "- Adding libc++_shared.so dependency for __cxa_demangle symbol"
patchelf --add-needed "libc++_shared.so" "$WORK_DIR/system/system/lib64/libMultiFrameProcessing20Core.camera.samsung.so"
LOG_STEP_OUT

LOG_STEP_IN "- Removing HDR10+ check"
if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt 36 ]]; then
    ADD_TO_WORK_DIR "pa3qzcx" "system" "system/lib64/libstagefright.so" 0 0 644 "u:object_r:system_lib_file:s0"
    HEX_PATCH "$WORK_DIR/system/system/lib64/libstagefright.so" \
        "010140f97069059420510034" \
        "010140f91f2003d51f2003d5"
elif [[ "$SOURCE_PLATFORM_SDK_VERSION" -eq 36 ]]; then
    # Android 16 changed the Camera::connect ABI. Replacing this library with
    # the older pa3qzcx blob makes zygote, cameraserver and the media services
    # fail at link time, so retain the source firmware's matched media stack.
    LOG "Skipping legacy HDR10+ blob on Android 16"
    ADD_TO_WORK_DIR "$SOURCE_FIRMWARE" "system" \
        "system/lib64/libstagefright.so" 0 0 644 \
        "u:object_r:system_lib_file:s0"
fi
LOG_STEP_IN "- Adding prebuilt libs from other devices"
BLOBS_LIST="
system/lib64/libc++_shared.so
"
for blob in $BLOBS_LIST
do
    ADD_TO_WORK_DIR "e2sxxx" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0"
done

BLOBS_LIST="
system/lib64/libeden_wrapper_system.so
system/lib64/libhigh_dynamic_range.arcsoft.so
system/lib64/liblow_light_hdr.arcsoft.so
system/lib64/libhigh_res.arcsoft.so
system/lib64/libsnap_aidl.snap.samsung.so
system/lib64/libsuperresolution.arcsoft.so
system/lib64/libsuperresolution_raw.arcsoft.so
system/lib64/libsuperresolution_wrapper_v2.camera.samsung.so
system/lib64/libsuperresolutionraw_wrapper_v2.camera.samsung.so
"
for blob in $BLOBS_LIST
do
    ADD_TO_WORK_DIR "p3sxxx" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0" &
done

# shellcheck disable=SC2046
wait $(jobs -p) || exit 1

LOG_STEP_OUT

LOG_STEP_IN "- Adding S21 (p3sxxx) SWISP models"
DELETE_FROM_WORK_DIR "vendor" "saiv/swisp_1.0"
ADD_TO_WORK_DIR "p3sxxx" "vendor" "saiv/swisp_1.0"

BLOBS_LIST="
system/lib64/libSwIsp_core.camera.samsung.so
system/lib64/libSwIsp_wrapper_v1.camera.samsung.so
"
for blob in $BLOBS_LIST
do
    ADD_TO_WORK_DIR "p3sxxx" "system" "$blob" 0 0 644 "u:object_r:system_lib_file:s0"
done
LOG_STEP_OUT

LOG_STEP_IN "- Adding S21 (p3sxxx) SingleTake models"
DELETE_FROM_WORK_DIR "vendor" "etc/singletake"
ADD_TO_WORK_DIR "p3sxxx" "vendor" "etc/singletake"

BLOBS_LIST="
system/priv-app/SingleTakeService/SingleTakeService.apk
system/cameradata/singletake/service-feature.xml
"
for blob in $BLOBS_LIST
do
    ADD_TO_WORK_DIR "p3sxxx" "system" "$blob" 0 0 644 "u:object_r:system_file:s0" &
done

# shellcheck disable=SC2046
wait $(jobs -p) || exit 1

LOG_STEP_OUT

LOG_STEP_IN "- Hardening the Exynos 990 snaplite session cleanup"
# O MotionPhoto da source envia o modelo BeepRemover (op TFLite 156) ao
# snap-service; o snaplite do S20+ (SNAP v22.09) não o registra, e
# SnapliteSession::Close() lia this+0x208 nulo, derrubando o serviço a cada
# foto. O desvio leva o ponteiro nulo à limpeza já existente em +0x27ec0; o
# app recebe a falha normal ("fail to open snap session"). Ver INSTRUCTIONS.md.
SNAPLITE_LIB="$WORK_DIR/vendor/lib64/libsnaplite_native.so"
SNAPLITE_CLOSE_FROM="680641f9083940f9080140f900a1009187ac0d94740641f97f0601f9"
SNAPLITE_CLOSE_TO="680641f9280600b4083940f9080140f900a1009186ac0d942c000014"
if [ -f "$SNAPLITE_LIB" ]; then
    if xxd -p -c 0 "$SNAPLITE_LIB" | grep -q "$SNAPLITE_CLOSE_FROM"; then
        HEX_PATCH "$SNAPLITE_LIB" "$SNAPLITE_CLOSE_FROM" "$SNAPLITE_CLOSE_TO" || exit 1
    elif ! xxd -p -c 0 "$SNAPLITE_LIB" | grep -q "$SNAPLITE_CLOSE_TO"; then
        LOG "- Unknown libsnaplite_native.so build; skipping Close() hardening"
    fi
fi
unset SNAPLITE_LIB SNAPLITE_CLOSE_FROM SNAPLITE_CLOSE_TO
LOG_STEP_OUT
