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
 * Called when event will be triggered.
 * Event listener allow you modify any event details (event name, data).
 *
 * @param szEventName   Event name.
 * @param iBufferLength Buffer size for storing event name.
 * @param hEventDetails Event details.
 *
 * @return  True if event should be written, false if blocked. 
 */
typedef DemoRec_EventListener = function bool (char[] szEventName, int iBufferLength, StringMap hEventDetails);

/**
 * Adds a event listener.
 *
 * @param szEventName   Event name for listening.
 * @param ptrListener   Pointer to listener.
 * @noreturn
 */
native void DemoRec_AddEventListener(const char[] szEventName, DemoRec_EventListener ptrListener);

/**
 * Removes a event listener.
 *
 * @param szEventName   Event name for stop listening.
 * @param ptrListener   Pointer to listener.
 * @noreturn
 */
native void DemoRec_RemoveEventListener(const char[] szEventName, DemoRec_EventListener ptrListener);

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

  // v1.1.1
  MarkNativeAsOptional("DemoRec_AddEventListener");
  MarkNativeAsOptional("DemoRec_RemoveEventListener");
}
#endif
