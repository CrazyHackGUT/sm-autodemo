/**
 * AutoDemo Recorder
 * Recorder for web-site
 * Copyright (C) 2018 CrazyHackGUT aka Kruzya
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
  version     = "1.0.2",
  author      = "CrazyHackGUT aka Kruzya",
  name        = "[AutoDemo] Core",
  url         = "https://kruzya.me"
};

/**
 * addons/sourcemod/data/demos/
 *
 * What we store in this directory?
 * -> Recorded demo file (*.dem)
 * -> Meta information (*.json)
 * -> Lock file, if demo recording (*.lock)
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
 * --> is_bot
 * -> events
 * --> event_name
 * --> time
 * --> data
 * ---> ... any data from module ...
 *      NOTE: we support only strings in data map.
 *      Any cell can't be added to JSON.
 */
char  g_szBaseDemoPath[PLATFORM_MAX_PATH];

ArrayList g_hUniquePlayers;
char      g_szDemoName[64];
char      g_szMapName[PLATFORM_MAX_PATH];
int       g_iStartTime;
bool      g_bRecording;
int       g_iEndTime;
ArrayList g_hEvents;

Handle    g_hCorePlugin;

/**
 * @section Events
 */
public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szError, int iBufferLength) {
  CreateNative("DemoRec_TriggerEvent",  API_TriggerEvent);

  CreateNative("DemoRec_IsRecording",   API_IsRecording);
  CreateNative("DemoRec_StartRecord",   API_StartRecord);
  CreateNative("DemoRec_StopRecord",    API_StopRecord);

  RegPluginLibrary("AutoDemo");

  g_hCorePlugin = hMySelf;
}

public void OnAllPluginsLoaded() {
  if (!SourceTV_IsActive())
    SetFailState("SourceTV bot is not active.");

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
  bool bIsBot = IsFakeClient(iClient);
  int iAccountID = (bIsBot ? 0 : GetSteamAccountID(iClient));
  char szName[32];
  GetClientName(iClient, szName, sizeof(szName));

  int iUniquePlayers = g_hUniquePlayers.Length;
  DataPack hPack;
  for (int iPlayer; iPlayer < iUniquePlayers; ++iPlayer) {
    hPack = g_hUniquePlayers.Get(iPlayer);
    hPack.Reset();
    if (hPack.ReadCell() == iAccountID) {
      hPack.Reset(true);
      hPack.WriteCell(iAccountID);
      hPack.WriteCell(bIsBot);
      hPack.WriteString(szName);

      return;
    }
  }

  hPack = new DataPack();
  hPack.WriteCell(iAccountID);
  hPack.WriteCell(bIsBot);
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

  DataPack hPack = new DataPack();
  hPack.WriteString(szEventName);
  hPack.WriteCell(GetTime());
  hPack.WriteCell(hEventData);
  g_hEvents.Push(hPack);
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
 * @section Recorder Manager
 */
void Recorder_Start() {
  char szDemoPath[PLATFORM_MAX_PATH];
  UTIL_GenerateUUID(g_szDemoName, sizeof(g_szDemoName));
  int iPos = FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);
  SourceTV_StartRecording(szDemoPath);

  strcopy(szDemoPath[iPos], sizeof(szDemoPath)-iPos, ".lock");
  UTIL_CreateEmptyFile(szDemoPath);
  g_bRecording = true;
  g_iStartTime = GetTime();

  g_hUniquePlayers = new ArrayList(ByteCountToCells(4));
  g_hEvents = new ArrayList(ByteCountToCells(4));

  for (int iClient = MaxClients; iClient != 0; --iClient)
    if (IsClientConnected(iClient) && IsClientAuthorized(iClient))
      OnClientAuthorized(iClient, NULL_STRING);
}

void Recorder_Stop() {
  int iRecordedTicks = SourceTV_GetRecordingTick();
  SourceTV_StopRecording();
  g_bRecording = false;
  g_iEndTime = GetTime();

  char szDemoPath[PLATFORM_MAX_PATH];
  int iPos = FormatEx(szDemoPath, sizeof(szDemoPath), "%s/%s", g_szBaseDemoPath, g_szDemoName);
  strcopy(szDemoPath[iPos], sizeof(szDemoPath)-iPos, ".lock");
  DeleteFile(szDemoPath);

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
  JSONObject  hPlayerJSON;
  JSONArray   hPlayers = new JSONArray();
  int iPlayersCount = g_hUniquePlayers.Length;
  for (int iPlayer; iPlayer < iPlayersCount; ++iPlayer) {
    hPlayerJSON = new JSONObject();
    hPlayerPack = g_hUniquePlayers.Get(iPlayer);
    hPlayerPack.Reset();

    hPlayerJSON.SetInt("account_id", hPlayerPack.ReadCell());
    hPlayerJSON.SetBool("is_bot", hPlayerPack.ReadCell());
    hPlayerPack.ReadString(szUserName, sizeof(szUserName));
    hPlayerPack.Close();
    hPlayerJSON.SetString("name", szUserName);

    hPlayers.Push(hPlayerJSON);
    hPlayerJSON.Close();
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
    hMap = hEventPack.ReadCell();
    hEventPack.Close();

    hEventDataJSON = UTIL_StringMapToJSON(hMap);
    hMap.Close();
    hEventJSON.Set("data", hEventDataJSON);
    hEventDataJSON.Close();
    hEvents.Push(hEventJSON);
  }
  hMetaInfo.Set("events", hEvents);
  hEvents.Close();
  g_hEvents.Clear();

  hMetaInfo.ToFile(szDemoPath);
  hMetaInfo.Close();
}

/**
 * @section UTILs
 */
void UTIL_CreateEmptyFile(const char[] szPath) {
  if (FileExists(szPath))
    return;

  File hFile = OpenFile(szPath, "wb");
  if (hFile)
    hFile.Close();
}

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
