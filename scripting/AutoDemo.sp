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

#include <AutoDemo>

#define AS(%0,%1) (view_as<%0>(%1))
#define JSArr(%0) AS(JSONArray, %0)
#define JSObj(%0) AS(JSONObject, %0)

#pragma newdecls  required
#pragma semicolon 1

public Plugin myinfo = {
  description = "Recorder Core for web-site",
  version     = "1.4.0 Alpha 3",
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

JSONObject g_hMetaInfo;

StringMap g_hEventListeners;
char      g_szDemoName[64];
char      g_szMapName[PLATFORM_MAX_PATH];
bool      g_bRecording;

Handle    g_hCorePlugin;

Handle    g_hStartRecordFwd;
Handle    g_hFinishRecordFwd;
Handle    g_hShouldWriteClientFwd;

/**
 * @section Events
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iBufferLength) {
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
}

public void OnAllPluginsLoaded() {
  // TODO: expose to config?
  BuildPath(Path_SM, g_szBaseDemoPath, sizeof(g_szBaseDemoPath), "data/demos");
}

public void OnMapStart() {
  GetCurrentMap(g_szMapName, sizeof(g_szMapName));
}

public void OnMapEnd() {
  if (g_bRecording)
    Recorder_Stop();
}

public void OnClientAuthorized(int iClient, const char[] szAuth) {
  if (!g_bRecording)
  {
    return;
  }

  // Don't write in metadata any bot.
  if (!API_IsShouldBeWrittenToMetadata(iClient))
  {
    return;
  }

  int iAccountID = GetSteamAccountID(iClient);
  char szName[128]; // csgo supports nicknames with length 128.
  GetClientName(iClient, szName, sizeof(szName));

  JSONArray hPlayers = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("players")));
  int iUniquePlayers = hPlayers.Length;
  JSONObject hPlayer;
  for (int iPlayer; iPlayer < iUniquePlayers; ++iPlayer) {
    hPlayer = JSObj(UTIL_LazyCloseHandle(hPlayers.Get(iPlayer)));

    if (hPlayer.GetInt("account_id") == iAccountID) {
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
  int iClient = GetNativeCell(iParamId);
  API_AssertIsValidClient(iClient);

  return iClient;
}

static void API_AssertIsValidClient(int iClient)
{
  if (0 > iClient || iClient > MaxClients)
  {
    ThrowNativeError(SP_ERROR_NATIVE, "Client ID %d is invalid", iClient);
  }

  if (IsFakeClient(iClient))
  {
    ThrowNativeError(SP_ERROR_NATIVE, "Client %d is a bot", iClient);
  }
}

static void API_AssertIsValidHandle(Handle hHandle, const char[] szFormatStr, any ...)
{
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
  // Find client in JSONArray.
  JSONArray hClients = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("players")));
  JSONObject hClient;

  int iClientCount = hClients.Length;
  for (int iClientId = 0; iClientId < iClientCount && !hClient; ++iClientId)
  {
    hClient = JSObj(UTIL_LazyCloseHandle(hClients.Get(iClientId)));
    if (hClient.GetInt("account_id") != iAccountID)
    {
      hClient = null;
    }
  }

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
  if (!g_bRecording)
    return; //ignore this event.

  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));

  StringMap hEventData = GetNativeCell(2);
  if (hEventData) {
    hEventData = view_as<StringMap>(UTIL_LazyCloseHandle(CloneHandle(hEventData, g_hCorePlugin)));
  }

  any data = (iNumParams < 3 ? 0 : GetNativeCell(3));
  if (!UTIL_TriggerEventListeners(szEventName, sizeof(szEventName), hEventData, data))
  {
    return;
  }

  JSONArray hEvents = JSArr(UTIL_LazyCloseHandle(g_hMetaInfo.Get("events")));
  JSONObject hEvent = JSObj(UTIL_LazyCloseHandle(new JSONObject()));
  hEvent.SetInt("time", GetTime());
  hEvent.SetInt("tick", SourceTV_GetRecordingTick());
  hEvent.SetString("event_name", szEventName);
  hEvent.Set("data", JSObj(UTIL_LazyCloseHandle(UTIL_StringMapToJSON(hEventData))));
  hEvents.Push(hEvent);
}

/**
 * Params for this native:
 * -> szEventName (string const)
 * -> ptrListener (DemoRec_EventListener)
 */
public int API_AddEventListener(Handle hPlugin, int iNumParams)
{
  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));

  UTIL_AddEventListener(szEventName, hPlugin, view_as<DemoRec_EventListener>(GetNativeFunction(2)));
}

/**
 * Params for this native:
 * -> szEventName (string const)
 * -> ptrListener (DemoRec_EventListener)
 */
public int API_RemoveEventListener(Handle hPlugin, int iNumParams)
{
  char szEventName[64];
  GetNativeString(1, szEventName, sizeof(szEventName));

  UTIL_RemoveEventListener(szEventName, hPlugin, view_as<DemoRec_EventListener>(GetNativeFunction(2)));
}

/**
 * Params for this native:
 * -> szField (string const)
 * -> szValue (string const)
 */
public int API_SetDemoData(Handle hPlugin, int iNumParams)
{
  if (!g_bRecording)
  {
    return;
  }

  char szField[64];
  char szValue[512];
  GetNativeString(1, szField, sizeof(szField));
  GetNativeString(2, szValue, sizeof(szValue));

  JSONObject hCustom = JSObj(UTIL_LazyCloseHandle(g_hMetaInfo.Get("data")));
  hCustom.SetString(szField, szValue);
}

/**
 * Params for this native:
 * null
 */
public int API_IsRecording(Handle hPlugin, int iNumParams)
{
  return g_bRecording;
}

/**
 * Params for this native:
 * null
 */
public int API_StartRecord(Handle hPlugin, int iNumParams)
{
  if (g_bRecording)
    return;

  Recorder_Start();
}

/**
 * Params for this native:
 * null
 */
public int API_StopRecord(Handle hPlugin, int iNumParams)
{
  if (!g_bRecording)
    return;

  Recorder_Stop();
}

/**
 * Params for this native:
 *
 * -> szBuffer
 * -> iLength
 */
public int API_GetDataDirectory(Handle hPlugin, int iNumParams)
{
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
  if (!g_bRecording)
    return 0;

  int iClient = API_AssertIsValidClientByParamID(1);
  int iAccountID = GetSteamAccountID(iClient);

  // Find client in ArrayList.
  JSONObject hClient = API_GetClientJSON(iAccountID);
  API_AssertIsValidHandle(hClient, "Couldn't find client %L in registered players", iClient);

  char szKey[128];
  char szValue[512];

  GetNativeString(2, szKey, sizeof(szKey));
  JSONObject hData = JSObj(UTIL_LazyCloseHandle(hClient.Get("data")));
  API_AssertIsValidHandle(hData, "Handle %x with client data %L is invalid", hData, iClient);

  if (hData.GetString(szKey, szValue, sizeof(szValue)))
  {
    SetNativeString(3, szValue, GetNativeCell(4), true);
    return true;
  }

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
  if (!g_bRecording)
    return 0;

  int iClient = API_AssertIsValidClientByParamID(1);
  int iAccountID = GetSteamAccountID(iClient);

  // Find client in ArrayList.
  JSONObject hClient = API_GetClientJSON(iAccountID);
  API_AssertIsValidHandle(hClient, "Couldn't find client %L in registered players", iClient);

  char szKey[128];
  char szValue[512];

  GetNativeString(2, szKey, sizeof(szKey));
  GetNativeString(3, szValue, sizeof(szValue));

  JSONObject hData = JSObj(UTIL_LazyCloseHandle(hClient.Get("data")));
  API_AssertIsValidHandle(hData, "Handle %x with client data %L is invalid", hData, iClient);

  if (!GetNativeCell(4) && hData.HasKey(szKey))
  {
    return 0;
  }

  hData.SetString(szKey, szValue);
  return 0;
}

bool API_IsShouldBeWrittenToMetadata(int iClient)
{
  Action eResult;

  Call_StartForward(g_hShouldWriteClientFwd);
  Call_PushCell(iClient);
  Call_Finish(eResult);

  return eResult < Plugin_Handled;
}

/**
 * @section Recorder Manager
 */
void Recorder_Start() {
  Recorder_Validate();

  char szDemoPath[PLATFORM_MAX_PATH];
  UTIL_GenerateUUID(g_szDemoName, sizeof(g_szDemoName));
  FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);
  SourceTV_StartRecording(szDemoPath);

  g_hMetaInfo = new JSONObject();
  g_hMetaInfo.SetString("unique_id", g_szDemoName);
  g_hMetaInfo.SetString("play_map", g_szMapName);
  g_hMetaInfo.SetInt("start_time", GetTime());
  g_hMetaInfo.Set("players", JSArr(UTIL_LazyCloseHandle(new JSONArray())));
  g_hMetaInfo.Set("events", JSArr(UTIL_LazyCloseHandle(new JSONArray())));
  g_hMetaInfo.Set("data", JSObj(UTIL_LazyCloseHandle(new JSONObject())));

  g_bRecording = true;

  for (int iClient = MaxClients; iClient != 0; --iClient)
    if (IsClientConnected(iClient) && IsClientAuthorized(iClient))
      OnClientAuthorized(iClient, NULL_STRING);

  Call_StartForward(g_hStartRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();
}

void Recorder_Stop() {
  Recorder_Validate();

  Call_StartForward(g_hFinishRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();

  int iRecordedTicks = SourceTV_GetRecordingTick();
  SourceTV_StopRecording();
  g_bRecording = false;

  char szDemoPath[PLATFORM_MAX_PATH];
  int iPos = FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);

  strcopy(szDemoPath[iPos], sizeof(szDemoPath)-iPos, ".json");
  g_hMetaInfo.SetInt("end_time",        GetTime());
  g_hMetaInfo.SetInt("recorded_ticks",  iRecordedTicks);
  g_hMetaInfo.ToFile(szDemoPath);
  g_hMetaInfo.Close();
}

void Recorder_Validate()
{
  if (!SourceTV_IsActive())
    SetFailState("SourceTV bot is not active."); // TODO: just throw an error? Native or general?
}

/**
 * @section UTILs
 */
int UTIL_GenerateUUID(char[] szBuffer, int iBufferLength) {
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
  JSONObject hJSON = new JSONObject();
  if (hMap) {
    StringMapSnapshot hShot = hMap.Snapshot();

    char szKey[256];
    char szValue[256];
    int iDataCount = hShot.Length;

    for (int iDataID; iDataID < iDataCount; ++iDataID) {
      hShot.GetKey(iDataID, szKey, sizeof(szKey));
      if (hMap.GetString(szKey, szValue, sizeof(szValue))) {
        hJSON.SetString(szKey, szValue);
      }
    }

    hShot.Close();
  }
  return hJSON;
}

bool UTIL_TriggerEventListeners(char[] szEventName, int iBufferLength, StringMap &hMap, any &data)
{
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
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
  DemoRec_EventListener ptrListener;
  DataPack hStorage;

  bool bResult;

  int iLength = hListeners.Length;
  for (int iListener = 0; iListener < iLength; ++iListener)
  {
    hStorage = hListeners.Get(iListener);
    hStorage.Reset();

    hPlugin = hStorage.ReadCell();
    ptrListener = view_as<DemoRec_EventListener>(hStorage.ReadFunction());

    Call_StartFunction(hPlugin, ptrListener);
    Call_PushStringEx(szEventName, iBufferLength, SM_PARAM_STRING_UTF8 | SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
    Call_PushCell(iBufferLength);
    Call_PushCell(hMap);
    Call_PushCellRef(data);
    Call_Finish(bResult);

    if (!bResult)
    {
      // Someone listener returned false.
      // Stop handling this event.
      return false;
    }
  }

  return true;
}

void UTIL_AddEventListener(const char[] szEventName, Handle hPlugin, DemoRec_EventListener ptrListener)
{
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
    hListeners = new ArrayList(ByteCountToCells(4));
    g_hEventListeners.SetValue(szEventName, hListeners);
  }

  DataPack hPack = new DataPack();
  hListeners.Push(hPack);

  hPack.WriteCell(hPlugin);
  hPack.WriteFunction(ptrListener);
}

void UTIL_RemoveEventListener(const char[] szEventName, Handle hPlugin, DemoRec_EventListener ptrListener)
{
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
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
    break;
  }
}

/**
 * Requests the closing handle in next frame and returns passed handle.
 *
 * @param     hHandle   Handle for lazy closing.
 * @return              Passed handle.
 */
stock Handle UTIL_LazyCloseHandle(Handle hHandle)
{
  if (hHandle)
  {
    RequestFrame(OnHandleShouldBeClosed, hHandle);
  }

  return hHandle;
}

static void OnHandleShouldBeClosed(Handle hHndl)
{
  hHndl.Close();
}
