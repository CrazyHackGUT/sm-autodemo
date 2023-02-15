/**
 * AutoDemo Recorder
 * Recorder for web-site
 * Copyright (C) 2018-2020 CrazyHackGUT aka Kruzya
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see http://www.gnu.org/licenses/
 */

#include <sourcemod>
#include <adt_array>
#include <ripext>
#include <sourcetvmanager>

// Debug Mode can be enabled here. Just remove two slashes
// before symbol "#"
//#define DEBUG_MODE

#include <AutoDemo>

#define AS(%0,%1) (view_as<%0>(%1))
#define JSArr(%0) AS(JSONArray, %0)
#define JSObj(%0) AS(JSONObject, %0)

#if defined DEBUG_MODE
  #define DBG(%0)       UTIL_DebugMessage(%0);
  #define SETUP_DBG()   BuildPath(Path_SM, g_szDebugLog, sizeof(g_szDebugLog), "logs/autodemo_debug.log");
#else
  #define DBG(%0)
  #define SETUP_DBG()
#endif

#pragma newdecls  required
#pragma semicolon 1

public Plugin myinfo = {
  description = "Recorder Core for web-site",
  version     = AUTODEMO_VERSION,
  author      = "CrazyHackGUT aka Kruzya",
  name        = "[AutoDemo] Core",
  url         = "https://kruzya.me"
};

/**
 * addons/sourcemod/data/demos/
 *
 * What we store in this directory?
 * -> Recorded demo file (*.dem)
 * -> Meta information (*.json). If file doesn't exists - demo records now.
 *
 * About meta:
 * -> play_map
 * -> recorded_ticks
 * -> unique_id (UUID v4; just for validating)
 * -> start_time
 * -> end_time
 * -> players (only unique players!)
 * --> account_id
 * --> name
 * --> data
 * ---> ... any data from module ...
 * -> events
 * --> event_name
 * --> time
 * --> tick
 * --> data
 * ---> ... any data from module ...
 * -> data
 * --> ... any data from module ...
 *
 *      NOTE: we support only strings in data map.
 *      Any cell can't be added to JSON.
 */
char  g_szBaseDemoPath[PLATFORM_MAX_PATH];

#if defined DEBUG_MODE
char      g_szDebugLog[PLATFORM_MAX_PATH];
#endif

JSONObject g_hMetaInfo;

StringMap g_hEventListeners;
char      g_szDemoName[64];
bool      g_bRecording;

Handle    g_hCorePlugin;

Handle    g_hStartRecordFwd;
Handle    g_hFinishRecordFwd;
Handle    g_hShouldWriteClientFwd;

/**
 * @section Events
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iBufferLength) {
  SETUP_DBG()
  DBG("AskPluginLoad2(%x, %d): Starting %s (API version %d)", hMySelf, bLate, AUTODEMO_VERSION, AUTODEMO_API_VERSION)

  CreateNative("DemoRec_TriggerEvent",  API_TriggerEvent);

  CreateNative("DemoRec_IsRecording",   API_IsRecording);
  CreateNative("DemoRec_StartRecord",   API_StartRecord);
  CreateNative("DemoRec_StopRecord",    API_StopRecord);

  CreateNative("DemoRec_GetDataDirectory", API_GetDataDirectory);

  CreateNative("DemoRec_GetClientData", API_GetClientData);
  CreateNative("DemoRec_SetClientData", API_SetClientData);

  CreateNative("DemoRec_AddEventListener",    API_AddEventListener);
  CreateNative("DemoRec_RemoveEventListener", API_RemoveEventListener);

  CreateNative("DemoRec_SetDemoData", API_SetDemoData);

  RegPluginLibrary("AutoDemo");

  g_hStartRecordFwd = CreateGlobalForward("DemoRec_OnRecordStart", ET_Ignore, Param_String);
  g_hFinishRecordFwd = CreateGlobalForward("DemoRec_OnRecordStop", ET_Ignore, Param_String);
  g_hShouldWriteClientFwd = CreateGlobalForward("DemoRec_OnClientPreRecordCheck", ET_Event, Param_Cell);

  g_hCorePlugin = hMySelf;
  g_hEventListeners = new StringMap();

  DBG("AskPluginLoad2(): Allocated memory for event listeners hashmap: pointer %x", g_hEventListeners)
  return APLRes_Success;
}

public void OnAllPluginsLoaded() {
  DBG("OnAllPluginsLoaded()")

  // TODO: expose to config?
  BuildPath(Path_SM, g_szBaseDemoPath, sizeof(g_szBaseDemoPath), "data/demos");
}

public void OnMapEnd() {
  DBG("OnMapEnd()")
  if (g_bRecording)
    Recorder_Stop();
}

public void OnClientAuthorized(int iClient, const char[] szAuth) {
  DBG("OnClientAuthorized(): %L (%s)", iClient, szAuth)
  if (!g_bRecording)
  {
    DBG("OnClientAuthorized(): %L -> demo is not recording. Skipped event.", iClient)
    return;
  }


  // Don't write in metadata any bot.
  if (!API_IsShouldBeWrittenToMetadata(iClient))
  {
    DBG("OnClientAuthorized(): %L -> player skipped from recording into demo-metadata.", iClient)
    return;
  }

  DBG("OnClientAuthorized(): %L -> inserting information", iClient)
  int iAccountID = GetSteamAccountID(iClient);
  char szName[128]; // csgo supports nicknames with length 128.
  GetClientName(iClient, szName, sizeof(szName));

  JSONArray hPlayers = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("players")));
  int iUniquePlayers = hPlayers.Length;
  JSONObject hPlayer;

  // TODO: refactor. Reuse API_GetClientJSON().
  for (int iPlayer; iPlayer < iUniquePlayers; ++iPlayer) {
    hPlayer = JSObj(UTIL_LazyCloseHandle(hPlayers.Get(iPlayer)));

    if (hPlayer.GetInt("account_id") == iAccountID) {
      DBG("OnClientAuthorized(): %L -> player is already is present in demo-metadata. Updating username...", iClient)
      hPlayer.SetString("name", szName);

      return;
    }
  }

  hPlayer = JSObj(UTIL_LazyCloseHandle(new JSONObject()));
  hPlayer.SetInt("account_id", iAccountID);
  hPlayer.SetString("name", szName);
  hPlayer.Set("data", JSObj(UTIL_LazyCloseHandle(new JSONObject())));
  hPlayers.Push(hPlayer);
}

/**
 * @section Helper functions for API
 */
static int API_AssertIsValidClientByParamID(int iParamId = 1)
{
  DBG("API_AssertIsValidClientByParamID(%d)", iParamId)

  int iClient = GetNativeCell(iParamId);
  API_AssertIsValidClient(iClient);

  return iClient;
}

static void API_AssertIsValidClient(int iClient)
{
  DBG("API_AssertIsValidClient(%d)", iClient)
  if (0 > iClient || iClient > MaxClients)
  {
    DBG("API_AssertIsValidClient(%d): Error. Client ID is invalid.", iClient)
    ThrowNativeError(SP_ERROR_NATIVE, "Client ID %d is invalid", iClient);
  }

  if (IsFakeClient(iClient))
  {
    DBG("API_AssertIsValidClient(%d): Error. Client is a bot.", iClient)
    ThrowNativeError(SP_ERROR_NATIVE, "Client %d is a bot", iClient);
  }

  DBG("API_AssertIsValidClient(%d): Player successfully validated.", iClient)
}

static void API_AssertIsValidHandle(Handle hHandle, const char[] szFormatStr, any ...)
{
  DBG("API_AssertIsValidHandle(%x)", hHandle)
  if (hHandle)
  {
    return;
  }

  char szErrorBuffer[512];
  VFormat(szErrorBuffer, sizeof(szErrorBuffer), szFormatStr, 3);
  ThrowNativeError(SP_ERROR_NATIVE, "%s", szErrorBuffer);
}

static JSONObject API_GetClientJSON(int iAccountID)
{
  DBG("API_GetClientJSON(%d)", iAccountID)

  // Find client in JSONArray.
  JSONArray hClients = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("players")));
  JSONObject hClient;

  int iClientCount = hClients.Length;
  for (int iClientId = 0; iClientId < iClientCount && !hClient; ++iClientId)
  {
    hClient = JSObj(UTIL_LazyCloseHandle(hClients.Get(iClientId)));
    DBG("API_GetClientJSON(%d): Fetched %x pointer from array. Checking...", iAccountID, hClient)
    if (hClient.GetInt("account_id") != iAccountID)
    {
      hClient = null;
    }
  }

  DBG("API_GetClientJSON(%d) -> %x", iAccountID, hClient)
  return hClient;
}

/**
 * @section Natives (API)
 */
/**
 * Params for this native:
 * -> szEventName (string const)
 * -> hMetaData (StringMap)
 */
public int API_TriggerEvent(Handle hPlugin, int iNumParams) {
  DBG("[TRACE] --> API_TriggerEvent()")
  if (!g_bRecording)
    return 0; //ignore this event.

  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));
  DBG("API_TriggerEvent(): Required event for triggering - \"%s\"", szEventName)

  StringMap hEventData = GetNativeCell(2);
  if (hEventData) {
    hEventData = view_as<StringMap>(UTIL_LazyCloseHandle(CloneHandle(hEventData, g_hCorePlugin)));
  }
  DBG("API_TriggerEvent(): Metadata with event stored on poiner %x", hEventData)

  any data = (iNumParams < 3 ? 0 : GetNativeCell(3));
  if (!UTIL_TriggerEventListeners(szEventName, sizeof(szEventName), hEventData, data))
  {
    DBG("API_TriggerEvent(): Event listeners is blocked writing event")
    return 0;
  }

  DBG("API_TriggerEvent(): Writing event %s with data stored on %x", szEventName, hEventData)
  JSONArray hEvents = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("events")));
  JSONObject hEvent = JSObj(UTIL_LazyCloseHandle(new JSONObject()));
  hEvent.SetInt("time", GetTime());
  hEvent.SetInt("tick", SourceTV_GetRecordingTick());
  hEvent.SetString("event_name", szEventName);
  hEvent.Set("data", JSObj(UTIL_LazyCloseHandle(UTIL_StringMapToJSON(hEventData))));
  hEvents.Push(hEvent);

  DBG("[TRACE] <-- API_TriggerEvent()")

  return 0;
}

/**
 * Params for this native:
 * -> szEventName (string const)
 * -> ptrListener (DemoRec_EventListener)
 */
public int API_AddEventListener(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_AddEventListener()")
  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));

  UTIL_AddEventListener(szEventName, hPlugin, GetNativeFunction(2));
  DBG("[TRACE] <-- API_AddEventListener()")

  return 0;
}

/**
 * Params for this native:
 * -> szEventName (string const)
 * -> ptrListener (DemoRec_EventListener)
 */
public int API_RemoveEventListener(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_RemoveEventListener()")
  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));

  UTIL_RemoveEventListener(szEventName, hPlugin, GetNativeFunction(2));
  DBG("[TRACE] <-- API_RemoveEventListener()")

  return 0;
}

/**
 * Params for this native:
 * -> szField (string const)
 * -> szValue (string const)
 */
public int API_SetDemoData(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_SetDemoData()")
  if (!g_bRecording)
  {
    DBG("[TRACE] <-- API_SetDemoData()")
    return 0;
  }

  char szField[64];
  char szValue[512];
  GetNativeString(1, szField, sizeof(szField));
  GetNativeString(2, szValue, sizeof(szValue));

  DBG("API_SetDemoData(): Setting value \"%s\" with key \"%s\"", szField, szValue)
  JSONObject hCustom = JSObj(UTIL_LazyCloseHandle(g_hMetaInfo.Get("data")));
  hCustom.SetString(szField, szValue);
  DBG("[TRACE] <-- API_SetDemoData()")

  return 0;
}

/**
 * Params for this native:
 * null
 */
public int API_IsRecording(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] <-> API_IsRecording()")
  return g_bRecording;
}

/**
 * Params for this native:
 * null
 */
public int API_StartRecord(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_StartRecord()")
  if (g_bRecording)
    return 0;

  Recorder_Start();
  DBG("[TRACE] <-- API_StartRecord()")
  return 0;
}

/**
 * Params for this native:
 * null
 */
public int API_StopRecord(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_StopRecord()")
  if (!g_bRecording)
    return 0;

  Recorder_Stop();
  DBG("[TRACE] <-- API_StopRecord()")
  return 0;
}

/**
 * Params for this native:
 *
 * -> szBuffer
 * -> iLength
 */
public int API_GetDataDirectory(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] <-> API_GetDataDirectory()")
  return SetNativeString(1, g_szBaseDemoPath, GetNativeCell(2));
}

/**
 * Params for this native:
 * -> iClient
 * -> szKey
 * -> szBuffer
 * -> iLength
 */
public int API_GetClientData(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_GetClientData()")
  if (!g_bRecording)
  {
    DBG("[TRACE] <-- API_GetClientData(): record is not running in this time")
    return 0;
  }

  int iClient = API_AssertIsValidClientByParamID(1);
  int iAccountID = GetSteamAccountID(iClient);

  // Find client in ArrayList.
  JSONObject hClient = API_GetClientJSON(iAccountID);
  API_AssertIsValidHandle(hClient, "Couldn't find client %L in registered players", iClient);

  char szKey[128];
  char szValue[512];

  DBG("API_GetClientData(): %L -> \"%s\"", iClient, szKey)
  GetNativeString(2, szKey, sizeof(szKey));
  JSONObject hData = JSObj(UTIL_LazyCloseHandle(hClient.Get("data")));
  API_AssertIsValidHandle(hData, "Handle %x with client data %L is invalid", hData, iClient);

  if (hData.GetString(szKey, szValue, sizeof(szValue)))
  {
    SetNativeString(3, szValue, GetNativeCell(4), true);
    DBG("[TRACE] <-- API_GetClientData(): success")
    return true;
  }

  DBG("[TRACE] <-- API_GetClientData(): failure")
  return false;
}

/**
 * Params for this native:
 * -> iClient
 * -> szKey
 * -> szValue
 * -> bRewrite
 */
public int API_SetClientData(Handle hPlugin, int iNumParams)
{
  DBG("[TRACE] --> API_SetClientData()")
  if (!g_bRecording)
  {
    DBG("[TRACE] <-- API_SetClientData(): record is not running in this time")
    return 0;
  }

  int iClient = API_AssertIsValidClientByParamID(1);
  int iAccountID = GetSteamAccountID(iClient);

  // Find client in ArrayList.
  JSONObject hClient = API_GetClientJSON(iAccountID);
  API_AssertIsValidHandle(hClient, "Couldn't find client %L in registered players", iClient);

  char szKey[128];
  char szValue[512];

  GetNativeString(2, szKey, sizeof(szKey));
  GetNativeString(3, szValue, sizeof(szValue));

  DBG("API_SetClientData(): %L -> \"%s\" ==> \"%s\"", iClient, szKey, szValue)
  JSONObject hData = JSObj(UTIL_LazyCloseHandle(hClient.Get("data")));
  API_AssertIsValidHandle(hData, "Handle %x with client data %L is invalid", hData, iClient);

  if (!GetNativeCell(4) && hData.HasKey(szKey))
  {
    DBG("[TRACE] <-- API_SetClientData(): key is already present, requested write in non-replace mode")
    return 0;
  }

  hData.SetString(szKey, szValue);
  DBG("[TRACE] <-- API_SetClientData(): success")
  return 0;
}

bool API_IsShouldBeWrittenToMetadata(int iClient)
{
  DBG("[TRACE] --> API_IsShouldBeWrittenToMetadata(): %L", iClient)
  Action eResult;

  Call_StartForward(g_hShouldWriteClientFwd);
  Call_PushCell(iClient);
  Call_Finish(eResult);

  bool bShouldBeWritten = (eResult < Plugin_Handled);
  DBG("[TRACE] <-- API_IsShouldBeWrittenToMetadata(): %d", bShouldBeWritten)
  return bShouldBeWritten;
}

/**
 * @section Recorder Manager
 */
void Recorder_Start() {
  DBG("[TRACE] --> Recorder_Start()")
  Recorder_Validate();

  char szDemoPath[PLATFORM_MAX_PATH];
  UTIL_GenerateUUID(g_szDemoName, sizeof(g_szDemoName));
  FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);

  DBG("Recorder_Start(): generated path %s", szDemoPath)
  SourceTV_StartRecording(szDemoPath);

  char szMapName[64];
  GetCurrentMap(szMapName, sizeof(szMapName));

  DBG("Recorder_Start(): configuring JSON with metadata about current demo")
  g_hMetaInfo = new JSONObject();
  g_hMetaInfo.SetString("unique_id", g_szDemoName);
  g_hMetaInfo.SetString("play_map", szMapName);
  g_hMetaInfo.SetInt("start_time", GetTime());
  g_hMetaInfo.Set("players", JSArr(UTIL_LazyCloseHandle(new JSONArray())));
  g_hMetaInfo.Set("events", JSArr(UTIL_LazyCloseHandle(new JSONArray())));
  g_hMetaInfo.Set("data", JSObj(UTIL_LazyCloseHandle(new JSONObject())));

  DBG("Recorder_Start(): switching internal recorder state to True")
  g_bRecording = true;

  DBG("Recorder_Start(): applying OnClientAuthorized hook for every authorized player")
  for (int iClient = MaxClients; iClient != 0; --iClient)
    if (IsClientConnected(iClient) && IsClientAuthorized(iClient))
      OnClientAuthorized(iClient, NULL_STRING);

  DBG("Recorder_Start(): requesting notification for every plugin")
  Call_StartForward(g_hStartRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();
  DBG("[TRACE] <-- Recorder_Start()")
}

void Recorder_Stop() {
  DBG("[TRACE] --> Recorder_Stop()")
  Recorder_Validate();

  DBG("Recorder_Stop(): requesting notification for every plugin")
  Call_StartForward(g_hFinishRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();

  int iRecordedTicks = SourceTV_GetRecordingTick();
  DBG("Recorder_Stop(): stopping recording with %d ticks", iRecordedTicks)
  SourceTV_StopRecording();
  g_bRecording = false;

  char szDemoPath[PLATFORM_MAX_PATH];
  int iPos = FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);

  strcopy(szDemoPath[iPos], sizeof(szDemoPath)-iPos, ".json");

  DBG("Recorder_Stop(): writing metadata to %s", szDemoPath)
  g_hMetaInfo.SetInt("end_time",        GetTime());
  g_hMetaInfo.SetInt("recorded_ticks",  iRecordedTicks);
  g_hMetaInfo.ToFile(szDemoPath);
  g_hMetaInfo.Close();

  DBG("[TRACE] <-- Recorder_Stop()")
}

void Recorder_Validate()
{
  DBG("[TRACE] --> Recorder_Validate()")
  if (!SourceTV_IsActive())
    SetFailState("SourceTV bot is not active."); // TODO: just throw an error? Native or general?
  DBG("[TRACE] <-- Recorder_Validate()")
}

/**
 * @section UTILs
 */
int UTIL_GenerateUUID(char[] szBuffer, int iBufferLength) {
  DBG("[TRACE] <-> UTIL_GenerateUUID()")
  return FormatEx(szBuffer, iBufferLength, "%04x%04x-%04x-%04x-%04x-%04x%04x%04x",
    // 32 bits for "time_low"
    GetRandomInt(0, 0xffff), GetRandomInt(0, 0xffff),

    // 16 bits for "time_mid"
    GetRandomInt(0, 0xffff),

    // 16 bits for "time_hi_and_version"
    // four most significant bits holds version number 4
    (GetRandomInt(0, 0x0fff) | 0x4000),

    // 16 bits, 8 bits for "clk_seq_hi_res",
    // 8 bits for "clk_seq_low",
    // two most significant bits holds zero and one for variant DCE1.1
    (GetRandomInt(0, 0x3fff) | 0x8000),

    // 48 bits for node
    GetRandomInt(0, 0xffff), GetRandomInt(0, 0xffff), GetRandomInt(0, 0xffff)
  );
}

JSONObject UTIL_StringMapToJSON(StringMap hMap) {
  DBG("[TRACE] --> UTIL_StringMapToJSON()")
  JSONObject hJSON = new JSONObject();
  DBG("UTIL_StringMapToJSON(): converting %x to %x", hMap, hJSON)

  if (hMap) {
    StringMapSnapshot hShot = hMap.Snapshot();
    DBG("UTIL_StringMapToJSON(): allocated temporary object StringMapSnapshot(%x) for fetching keys from %x", hShot, hMap)

    char szKey[256];
    char szValue[256];
    int iDataCount = hShot.Length;

    for (int iDataID; iDataID < iDataCount; ++iDataID) {
      hShot.GetKey(iDataID, szKey, sizeof(szKey));
      DBG("UTIL_StringMapToJSON(): retrieved key \"%s\"", szKey)
      if (hMap.GetString(szKey, szValue, sizeof(szValue))) {
        DBG("UTIL_StringMapToJSON(): retrieved value \"%s\"", szValue)
        hJSON.SetString(szKey, szValue);
      }
    }

    DBG("UTIL_StringMapToJSON(): closing temporary object StringMapSnapshot(%x)", hShot)
    hShot.Close();
  }

  DBG("[TRACE] <-- UTIL_StringMapToJSON()")
  return hJSON;
}

bool UTIL_TriggerEventListeners(char[] szEventName, int iBufferLength, StringMap &hMap, any &data)
{
  DBG("[TRACE] --> UTIL_TriggerEventListeners()")
  DBG("UTIL_TriggerEventListener(): \"%s\", %x, %d", szEventName, hMap, data)
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
    DBG("UTIL_TriggerEventListeners(): no one event handler is registered for \"%s\"", szEventName)
    DBG("[TRACE] <-- UTIL_TriggerEventListeners()")
    // event listeners is not registered for this event.
    // so just allow writing this event.
    return true;
  }

  // Setup StringMap with event details, if it doesn't exists.
  // We're should guarantee for our plugin listeners in existing
  // this handle.
  if (hMap == null)
  {
    hMap = new StringMap();
  }

  // Call all listeners.
  Handle hPlugin;
  Function ptrListener;
  DataPack hStorage;

  bool bResult;

  int iLength = hListeners.Length;
  for (int iListener = 0; iListener < iLength; ++iListener)
  {
    hStorage = hListeners.Get(iListener);
    hStorage.Reset();

    hPlugin = hStorage.ReadCell();
    ptrListener = hStorage.ReadFunction();
    DBG("[TRACE] --> UTIL_TriggerEventListeners()->Closure(Plugin(%x),  Function(%x))", hPlugin, view_as<int>(ptrListener))

    Call_StartFunction(hPlugin, ptrListener);
    Call_PushStringEx(szEventName, iBufferLength, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
    Call_PushCell(iBufferLength);
    Call_PushCell(hMap);
    Call_PushCellRef(data);
    Call_Finish(bResult);

    DBG("[TRACE] <-- UTIL_TriggerEventListeners()->Closure(Plugin(%x),  Function(%x))", hPlugin, view_as<int>(ptrListener))

    if (!bResult)
    {
      DBG("UTIL_TriggerEventListeners(): returned blocking event writing from handler.")
      DBG("[TRACE] <-- UTIL_TriggerEventListeners()")
      // Someone listener returned false.
      // Stop handling this event.
      return false;
    }
  }

  DBG("[TRACE] <-- UTIL_TriggerEventListeners()")
  return true;
}

void UTIL_AddEventListener(const char[] szEventName, Handle hPlugin, Function ptrListener)
{
  DBG("[TRACE] --> UTIL_AddEventListener()")
  DBG("UTIL_AddEventListener(): \"%s\", Plugin(%x), Function(%x)", szEventName, hPlugin, view_as<int>(ptrListener))
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
    DBG("UTIL_AddEventListener(): first event listener is registered. Allocating memory for storing all possible event handlers.")
    hListeners = new ArrayList(ByteCountToCells(4));
    g_hEventListeners.SetValue(szEventName, hListeners);
  }

  DataPack hPack = new DataPack();
  hListeners.Push(hPack);

  hPack.WriteCell(hPlugin);
  hPack.WriteFunction(ptrListener);
  DBG("[TRACE] <-- UTIL_AddEventListener()")
}

void UTIL_RemoveEventListener(const char[] szEventName, Handle hPlugin, Function ptrListener)
{
  DBG("[TRACE] --> UTIL_RemoveEventListener()")
  DBG("UTIL_RemoveEventListener(): \"%s\", Plugin(%x), Function(%x)", szEventName, hPlugin, view_as<int>(ptrListener))
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
    DBG("UTIL_RemoveEventListener(): no one event handler is registered for \"%s\". Stopping.", szEventName)
    DBG("[TRACE] <-- UTIL_RemoveEventListener()")
    // This no has meaning. Just stop.
    return;
  }

  DataPack hPack;
  int iEventListeners = hListeners.Length;
  for (int iEventListener = 0; iEventListener < iEventListeners; ++iEventListener)
  {
    hPack = hListeners.Get(iEventListener);
    hPack.Reset();

    if (hPack.ReadCell() != hPlugin)
    {
      continue;
    }

    if (hPack.ReadFunction() != ptrListener)
    {
      continue;
    }

    hPack.Close();
    hListeners.Erase(iEventListener);
    DBG("UTIL_RemoveEventListener(): Event handler is found and removed.")
    break;
  }

  DBG("[TRACE] <-- UTIL_RemoveEventListener()")
}

/**
 * Requests the closing handle in next frame and returns passed handle.
 *
 * @param     hHandle   Handle for lazy closing.
 * @return              Passed handle.
 */
stock Handle UTIL_LazyCloseHandle(Handle hHandle)
{
  DBG("[TRACE] --> UTIL_LazyCloseHandle()")
  if (hHandle)
  {
    DBG("UTIL_LazyCloseHandle(): registered closing handler for %x", hHandle)
    RequestFrame(OnHandleShouldBeClosed, hHandle);
  }

  DBG("[TRACE] <-- UTIL_LazyCloseHandle()")
  return hHandle;
}

static void OnHandleShouldBeClosed(Handle hHndl)
{
  DBG("[TRACE] --> OnHandleShouldBeClosed()")
  DBG("OnHandleShouldBeClosed: closing handle %x", hHndl)
  hHndl.Close();
  DBG("[TRACE] <-- OnHandleShouldBeClosed()")
}

/**
 * @section DEBUGGING
 */
#if defined DEBUG_MODE
void UTIL_DebugMessage(const char[] szFormatMsg, any ...) {
  char szMessage[1024];
  VFormat(szMessage, sizeof(szMessage), szFormatMsg, 2);

  LogToFile(g_szDebugLog, "%s", szMessage);
}
#endif
