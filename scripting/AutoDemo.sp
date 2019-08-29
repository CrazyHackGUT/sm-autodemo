/**
 * AutoDemo Recorder
 * Recorder for web-site
 * Copyright (C) 2018-2019 CrazyHackGUT aka Kruzya
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

#pragma newdecls  required
#pragma semicolon 1

public Plugin myinfo = {
  description = "Recorder Core for web-site",
  version     = "1.2.1",
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

StringMap g_hEventListeners;
ArrayList g_hUniquePlayers;
char      g_szDemoName[64];
char      g_szMapName[PLATFORM_MAX_PATH];
int       g_iStartTime;
int       g_iStartTick;
bool      g_bRecording;
int       g_iEndTime;
ArrayList g_hEvents;
StringMap g_hCustom;

Handle    g_hCorePlugin;

Handle    g_hStartRecordFwd;
Handle    g_hFinishRecordFwd;

/**
 * @section Events
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iBufferLength) {
  CreateNative("DemoRec_TriggerEvent",  API_TriggerEvent);

  CreateNative("DemoRec_IsRecording",   API_IsRecording);
  CreateNative("DemoRec_StartRecord",   API_StartRecord);
  CreateNative("DemoRec_StopRecord",    API_StopRecord);

  CreateNative("DemoRec_SetClientData", API_SetClientData);

  CreateNative("DemoRec_AddEventListener",    API_AddEventListener);
  CreateNative("DemoRec_RemoveEventListener", API_RemoveEventListener);

  CreateNative("DemoRec_SetDemoData", API_SetDemoData);

  RegPluginLibrary("AutoDemo");

  g_hStartRecordFwd = CreateGlobalForward("DemoRec_OnRecordStart", ET_Ignore, Param_String);
  g_hFinishRecordFwd = CreateGlobalForward("DemoRec_OnRecordStop", ET_Ignore, Param_String);

  g_hCorePlugin = hMySelf;
  g_hEventListeners = new StringMap();
}

public void OnAllPluginsLoaded() {
  BuildPath(Path_SM, g_szBaseDemoPath, sizeof(g_szBaseDemoPath), "data/demos/");
}

public void OnMapStart() {
  GetCurrentMap(g_szMapName, sizeof(g_szMapName));
}

public void OnMapEnd() {
  if (g_bRecording)
    Recorder_Stop();
}

public void OnClientAuthorized(int iClient, const char[] szAuth) {
  // Don't write in metadata any bot.
  if (IsFakeClient(iClient) || !g_bRecording)
  {
    return;
  }

  int iAccountID = GetSteamAccountID(iClient);
  char szName[32];
  GetClientName(iClient, szName, sizeof(szName));

  int iUniquePlayers = g_hUniquePlayers.Length;
  DataPack hPack;
  for (int iPlayer; iPlayer < iUniquePlayers; ++iPlayer) {
    hPack = g_hUniquePlayers.Get(iPlayer);
    hPack.Reset();
    if (hPack.ReadCell() == iAccountID) {
      StringMap hMap = hPack.ReadCell();

      hPack.Reset(true);
      hPack.WriteCell(iAccountID);
      hPack.WriteCell(hMap);
      hPack.WriteString(szName);

      return;
    }
  }

  hPack = new DataPack();
  hPack.WriteCell(iAccountID);
  hPack.WriteCell(new StringMap());
  hPack.WriteString(szName);
  g_hUniquePlayers.Push(hPack);
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
    hEventData = view_as<StringMap>(CloneHandle(hEventData, g_hCorePlugin));
  }

  any data = (iNumParams < 3 ? 0 : GetNativeCell(3));
  if (!UTIL_TriggerEventListeners(szEventName, sizeof(szEventName), hEventData, data))
  {
    if (hEventData) hEventData.Close();
    return;
  }

  DataPack hPack = new DataPack();
  hPack.WriteString(szEventName);
  hPack.WriteCell(GetTime());
  hPack.WriteCell(GetGameTickCount() - g_iStartTick);
  hPack.WriteCell(hEventData);
  g_hEvents.Push(hPack);
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

  g_hCustom.SetString(szField, szValue);
}

/**
 * Params for this native:
 * null
 */
public int API_IsRecording(Handle hPlugin, int iNumParams) {
  return g_bRecording;
}

/**
 * Params for this native:
 * null
 */
public int API_StartRecord(Handle hPlugin, int iNumParams) {
  if (g_bRecording)
    return;

  Recorder_Start();
}

/**
 * Params for this native:
 * null
 */
public int API_StopRecord(Handle hPlugin, int iNumParams) {
  if (!g_bRecording)
    return;

  Recorder_Stop();
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

  int iClient = GetNativeCell(1);
  if (0 < iClient || iClient > MaxClients)
  {
    return ThrowNativeError(SP_ERROR_NATIVE, "Client ID %d is invalid", iClient);
  }

  if (IsFakeClient(iClient))
  {
    return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is a bot", iClient);
  }

  int iAccountID = GetSteamAccountID(iClient);

  // Find client in ArrayList.
  DataPack hClient;
  int iClientCount = g_hUniquePlayers.Length;
  for (int iClientId = 0; iClientId < iClientCount && !hClient; ++iClientId)
  {
    hClient = g_hUniquePlayers.Get(iClientId);
    hClient.Reset();

    if (hClient.ReadCell() != iAccountID)
    {
      hClient = null;
    }
  }

  if (!hClient)
  {
    return ThrowNativeError(SP_ERROR_NATIVE, "Couldn't find client %d is registered players", iClient);
  }

  char szKey[128];
  char szValue[512];

  GetNativeString(2, szKey, sizeof(szKey));
  GetNativeString(3, szValue, sizeof(szValue));

  StringMap hMap = hClient.ReadCell();
  hMap.SetString(szKey, szValue, GetNativeCell(4));
  return 0;
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

  g_bRecording = true;
  g_iStartTime = GetTime();

  g_hUniquePlayers = new ArrayList(ByteCountToCells(4));
  g_hEvents = new ArrayList(ByteCountToCells(4));
  g_hCustom = new StringMap();
  g_iStartTick = GetGameTickCount();

  for (int iClient = MaxClients; iClient != 0; --iClient)
    if (IsClientConnected(iClient) && IsClientAuthorized(iClient))
      OnClientAuthorized(iClient, NULL_STRING);

  Call_StartForward(g_hStartRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();
}

void Recorder_Stop() {
  Recorder_Validate();

  Call_StartForward(g_hStopRecordFwd);
  Call_PushString(g_szDemoName);
  Call_Finish();

  int iRecordedTicks = SourceTV_GetRecordingTick();
  SourceTV_StopRecording();
  g_bRecording = false;
  g_iEndTime = GetTime();

  char szDemoPath[PLATFORM_MAX_PATH];
  int iPos = FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);

  strcopy(szDemoPath[iPos], sizeof(szDemoPath)-iPos, ".json");
  JSONObject hMetaInfo = new JSONObject();
  hMetaInfo.SetInt("start_time",      g_iStartTime);
  hMetaInfo.SetInt("end_time",        g_iEndTime);
  hMetaInfo.SetInt("recorded_ticks",  iRecordedTicks);
  hMetaInfo.SetString("unique_id",    g_szDemoName);
  hMetaInfo.SetString("play_map",     g_szMapName);

  // add players to JSON.
  char szUserName[128]; // csgo supports nicknames with length 128.

  DataPack    hPlayerPack;
  StringMap   hCustomFields;
  JSONObject  hPlayerJSON;
  JSONObject  hPlayerFields;
  JSONArray   hPlayers = new JSONArray();
  int iPlayersCount = g_hUniquePlayers.Length;
  for (int iPlayer; iPlayer < iPlayersCount; ++iPlayer) {
    hPlayerJSON = new JSONObject();
    hPlayerPack = g_hUniquePlayers.Get(iPlayer);
    hPlayerPack.Reset();

    hPlayerJSON.SetInt("account_id", hPlayerPack.ReadCell());
    hCustomFields = hPlayerPack.ReadCell();
    hPlayerPack.ReadString(szUserName, sizeof(szUserName));
    hPlayerPack.Close();
    hPlayerJSON.SetString("name", szUserName);

    hPlayerFields = UTIL_StringMapToJSON(hCustomFields);
    hPlayerJSON.Set("data", hPlayerFields);

    hPlayers.Push(hPlayerJSON);
    hPlayerJSON.Close();
    hCustomFields.Close();
    hPlayerFields.Close();
  }
  hMetaInfo.Set("players", hPlayers);
  hPlayers.Close();
  g_hUniquePlayers.Clear();

  // add events.
  char szEventName[64];

  DataPack    hEventPack;
  JSONObject  hEventJSON;
  JSONObject  hEventDataJSON;
  StringMap   hMap;
  JSONArray   hEvents = new JSONArray();
  int iEventsCount = g_hEvents.Length;
  for (int iEvent; iEvent < iEventsCount; ++iEvent) {
    hEventJSON = new JSONObject();
    hEventPack = g_hEvents.Get(iEvent);
    hEventPack.Reset();

    hEventPack.ReadString(szEventName, sizeof(szEventName));
    hEventJSON.SetString("event_name", szEventName);

    hEventJSON.SetInt("time", hEventPack.ReadCell());
    hEventJSON.SetInt("tick", hEventPack.ReadCell());
    hMap = hEventPack.ReadCell();
    hEventPack.Close();

    hEventDataJSON = UTIL_StringMapToJSON(hMap);
    hMap.Close();
    hEventJSON.Set("data", hEventDataJSON);
    hEventDataJSON.Close();
    hEvents.Push(hEventJSON);
    hEventJSON.Close();
  }
  hMetaInfo.Set("events", hEvents);
  hEvents.Close();
  g_hEvents.Clear();

  // add custom fields.
  JSONObject hDemoFields = UTIL_StringMapToJSON(g_hCustom);
  hMetaInfo.Set("data", hDemoFields);
  hDemoFields.Close();
  g_hCustom.Close();

  hMetaInfo.ToFile(szDemoPath);
  hMetaInfo.Close();
}

void Recorder_Validate()
{
  if (!SourceTV_IsActive())
    SetFailState("SourceTV bot is not active.");
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

bool UTIL_TriggerEventListeners(char[] szEventName, int iBufferLength, StringMap hMap, any data)
{
  ArrayList hListeners;
  if (!g_hEventListeners.GetValue(szEventName, hListeners))
  {
    // event listeners is not registered for this event.
    // so just allow writing this event.
    return true;
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