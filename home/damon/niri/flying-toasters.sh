# SDL inhibits compositor idle detection and releases inhibition on exit/crash.
# Leave swayidle running so explicit locking and before-sleep still work.
exec 9>"${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/flying-toasters.lock"
flock --nonblock 9 || exit 0
export SDL_VIDEODRIVER=wayland
export SDL_VIDEO_ALLOW_SCREENSAVER=0
exec flying-toasters
