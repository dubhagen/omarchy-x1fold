// Sets libinput's disable-while-typing timeout. Hyprland 0.56 only exposes
// the on/off switch. The long pause (default 500 ms, range 100–5000) is what
// runs after typing has started. The first key of a gap stays at libinput's
// fixed 200 ms latch; that one is not configurable.
//
// Built against the installed Hyprland headers. setup.sh passes -fno-gnu-unique
// so this .so does not replace the compositor's inline globals. The input
// manager is taken from the main executable with dlsym.

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>

#include <aquamarine/input/Input.hpp>

#include <libinput.h>

#include <dlfcn.h>

#include <string>

static constexpr uint32_t DWT_TIMEOUT_MS = 1500;

static HANDLE                    g_handle = nullptr;
static SP<SHyprCtlCommand>       g_cmd;

static CInputManager* input_manager() {
    // dlopen(nullptr) is the main program, which owns the live manager.
    void* main = dlopen(nullptr, RTLD_LAZY | RTLD_NOLOAD);
    if (!main)
        return nullptr;
    auto* slot = static_cast<UP<CInputManager>*>(dlsym(main, "g_pInputManager"));
    if (!slot || !slot->get())
        return nullptr;
    return slot->get();
}

static std::string apply_timeout() {
    auto* mgr = input_manager();
    if (!mgr)
        return "no input manager\n";

    std::string out;
    for (const auto& pointer : mgr->m_pointers) {
        if (!pointer || !pointer->aq())
            continue;
        libinput_device* device = pointer->aq()->getLibinputHandle();
        if (!device || !libinput_device_config_dwt_is_available(device))
            continue;
        const char* name = libinput_device_get_name(device);
        const auto  status = libinput_device_config_dwt_set_timeout(device, DWT_TIMEOUT_MS);
        const auto  got    = libinput_device_config_dwt_get_timeout(device);
        out += name ? name : "touchpad";
        out += " ";
        out += std::to_string(got);
        if (status != LIBINPUT_CONFIG_STATUS_SUCCESS) {
            out += " failed";
        }
        out += "\n";
    }
    if (out.empty())
        out = "no touchpad with disable-while-typing\n";
    return out;
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    g_handle = handle;

    const auto version = HyprlandAPI::getHyprlandVersion(handle);
    if (version.hash != GIT_COMMIT_HASH) {
        return {"x1fold-dwt", "disabled, Hyprland changed; run setup.sh to rebuild", "dubhagen", "1"};
    }

    SHyprCtlCommand cmd;
    cmd.name  = "x1folddwt";
    cmd.exact = true;
    cmd.fn    = [](eHyprCtlOutputFormat, std::string) { return apply_timeout(); };
    g_cmd     = HyprlandAPI::registerHyprCtlCommand(handle, cmd);

    apply_timeout();

    return {"x1fold-dwt", "Keep the touchpad off for 1500 ms after typing", "dubhagen", "1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_handle = nullptr;
}
