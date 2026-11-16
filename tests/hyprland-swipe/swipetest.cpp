// Test plugin for the grid-swipe patch (patches/hyprland-grid-swipe.patch).
//
// Lets a Lua script drive Hyprland's trackpad gesture code with synthetic swipes, in
// controlled steps, and read back where each workspace is drawn while the swipe is
// still in progress. Modelled on Hyprland's own hyprtester plugin. Not for real use:
// load it only into a throwaway (nested) Hyprland.
//
//   hl.plugin.swipetest.begin()
//   hl.plugin.swipetest.update(fingers, dx, dy)   -- one step of finger movement
//   hl.plugin.swipetest.finish()
//   hl.plugin.swipetest.offset(workspace_id)      -- x, y render offset (nil if none)

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/managers/input/trackpad/TrackpadGestures.hpp>
#include <hyprland/src/desktop/Workspace.hpp>
#include <hyprland/src/devices/IPointer.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

inline HANDLE PHANDLE = nullptr;

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static int luaBegin(lua_State*) {
    g_pTrackpadGestures->gestureBegin(IPointer::SSwipeBeginEvent{});
    return 0;
}

static int luaUpdate(lua_State* L) {
    const auto fingers = (uint32_t)luaL_checkinteger(L, 1);
    const auto dx      = luaL_checknumber(L, 2);
    const auto dy      = luaL_checknumber(L, 3);
    g_pTrackpadGestures->gestureUpdate(IPointer::SSwipeUpdateEvent{.fingers = fingers, .delta = {dx, dy}});
    return 0;
}

static int luaFinish(lua_State*) {
    g_pTrackpadGestures->gestureEnd(IPointer::SSwipeEndEvent{});
    return 0;
}

static int luaOffset(lua_State* L) {
    const auto ws = g_pCompositor->getWorkspaceByID((WORKSPACEID)luaL_checkinteger(L, 1));
    if (!ws)
        return 0;
    const auto v = ws->m_renderOffset->value();
    lua_pushnumber(L, v.x);
    lua_pushnumber(L, v.y);
    return 2;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    HyprlandAPI::addLuaFunction(PHANDLE, "swipetest", "begin", luaBegin);
    HyprlandAPI::addLuaFunction(PHANDLE, "swipetest", "update", luaUpdate);
    HyprlandAPI::addLuaFunction(PHANDLE, "swipetest", "finish", luaFinish);
    HyprlandAPI::addLuaFunction(PHANDLE, "swipetest", "offset", luaOffset);

    return {"swipetest", "synthetic trackpad swipes for testing", "test", "0"};
}

APICALL EXPORT void PLUGIN_EXIT() {}
