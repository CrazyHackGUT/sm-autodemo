#if defined _AutoDemo_included
  #endinput
#endif
#define _AutoDemo_included

/**
 * @section Natives
 */
/**
 * Returns the recording state.
 *
 * @return  True, if demo records.
 */
native bool DemoRec_IsRecording();

/**
 * Starts recording, if we don't record any demo already.
 *
 * @noreturn
 */
native void DemoRec_StartRecord();

/**
 * Stops recording, if we record demo.
 *
 * @noreturn
 */
native void DemoRec_StopRecord();

/**
 * Adds a event to metainfo for demo.
 *
 * @param szEventName   Event name for including in JSON.
 *                      We recommend use something simple, like 'game_round_start'
 *                      If web supports, event should be rendered on demo log.
 * @param hData         StringMap with any custom data. We support only string in values.
 *                      Optional.
 * @note                We clones your StringMap, if he passed to function. So, please, close StringMap handle after passing.
 */
native void DemoRec_TriggerEvent(const char[] szEventName, StringMap hData = null);

/**
 * Adds a custom field for client.
 *
 * @param iClient       Client identifier.
 * @param szKey         Key name.
 * @param szValue       Value.
 * @param bRewrite      Pass true, if you want rewrite already written value.
 *
 * @error Client is invalid or bot.
 */
native void DemoRec_SetClientData(int iClient, const char[] szKey, const char[] szValue, bool bRewrite = false);

/**
 * DO NOT EDIT ANYTHING AFTER THIS LINES!
 */
public SharedPlugin __pl_AutoDemo = {
  name      = "AutoDemo",
  file      = "AutoDemo/Core.smx",
#if defined REQUIRE_PLUGIN
  required  = 1,
#else
  required  = 0,
#endif
};

#if !defined _REQUIRE_PLUGIN
public void __pl_AutoDemo_SetNTVOptional() {
  // v1.0.0
  MarkNativeAsOptional("DemoRec_TriggerEvent");
  MarkNativeAsOptional("DemoRec_IsRecording");
  MarkNativeAsOptional("DemoRec_StartRecord");
  MarkNativeAsOptional("DemoRec_StopRecord");

  // v1.0.5
  MarkNativeAsOptional("DemoRec_SetClientData");
}
#endif
