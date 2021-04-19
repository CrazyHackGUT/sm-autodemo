/**
 * AutoDemo Recorder - Event Manager
 * Copyright (C) 2019-2020 CrazyHackGUT aka Kruzya
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
#include <events>

#include <AutoDemo>

#pragma newdecls  required
#pragma semicolon 1

public Plugin myinfo = {
  description = "Handles all generic events",
  version     = "1.0.10",
  author      = "CrazyHackGUT aka Kruzya",
  name        = "[AutoDemo] Event Manager",
  url         = "https://kruzya.me"
};

char    g_szRoundStartEvent[64];
char    g_szRoundEndEvent[64];
char    g_szKillClient[32];
char    g_szKillVictim[32];
char    g_szKill[64];

ConVar  g_hRecordMode, g_hMinPlayers;
int     g_iRecordMode, g_iMinPlayers;

bool    g_bRoundRecord = true;

/**
 * @section Events
 */
public void OnPluginStart()
{
  Handle hGameConf = LoadGameConfigFile("autodemo_events");
  if (!hGameConf)
  {
    SetFailState("Can't load gamedata: file not found or has invalid structure");
    return;
  }

  if (!UTIL_GetEventName(hGameConf,  "Round Start",   g_szRoundStartEvent,  sizeof(g_szRoundStartEvent)) ||
      !UTIL_GetEventName(hGameConf,  "Round End",     g_szRoundEndEvent,    sizeof(g_szRoundEndEvent)))
  {
    LogError("NOTE: Round records is not available.");
    g_bRoundRecord = false;
  }

  if (UTIL_GetEventName(hGameConf,  "Player Kill",   g_szKill,             sizeof(g_szKill)))
  {
    UTIL_GetField(hGameConf, "Player Kill - Client",  g_szKillClient, sizeof(g_szKillClient));
    UTIL_GetField(hGameConf, "Player Kill - Victim",  g_szKillVictim, sizeof(g_szKillVictim));

    if (!g_szKillClient[0] || !g_szKillVictim[0])
    {
      LogError("Event with kills is not possible to record: fields with client or victim name is undefined.");
    }
  }

  hGameConf.Close();

  g_hRecordMode = CreateConVar("sm_autodemo_recordmode", "1", "0 - disabled\n1 - record maps\n2 - record events", _, true, 0.0, true, 2.0);
  g_hMinPlayers = CreateConVar("sm_autodemo_minplayers", "4", "Player count required for starting record\nNOTE: This value for map recording works different. Demo stops in end round if limit isn't completes, and starts in start round.", _, true, 0.0);
  HookConVarChange(g_hRecordMode, OnRecordModeChanged);
  HookConVarChange(g_hMinPlayers, OnMinPlayersChanged);
}

public void OnMapStart()
{
  // Try skip first 1000 ticks.
  RequestFrame(OnMapStart_Post, 1000);
}

public void OnMapStart_Post(any data)
{
  if (data != 0)
  {
    RequestFrame(OnMapStart_Post, data-1);
    return;
  }

  bool bIsRecording = DemoRec_IsRecording();
  if (g_iRecordMode == 1 && !bIsRecording && UTIL_CheckPlayers())
  {
    DemoRec_StartRecord();
    bIsRecording = true;
  }

  bIsRecording && DemoRec_TriggerEvent("Core:MapStart");
}

public void OnMapEnd()
{
  if (DemoRec_IsRecording())
  {
    DemoRec_TriggerEvent("Core:MapEnd");

    g_iRecordMode == 1 && DemoRec_StopRecord();
  }
}

public void OnClientAuthorized(int iClient)
{
  if (!DemoRec_IsRecording())
  {
    return;
  }

  StringMap hMap = new StringMap();
  UTIL_WriteClient(hMap, "client", iClient);
  DemoRec_TriggerEvent("Core:ClientAuth", hMap);
  hMap.Close();
}

public void OnClientDisconnect(int iClient)
{
  if (!DemoRec_IsRecording())
  {
    return;
  }

  StringMap hMap = new StringMap();
  UTIL_WriteClient(hMap, "client", iClient);
  DemoRec_TriggerEvent("Core:ClientDisconnect", hMap);
  hMap.Close();
}

public void OnClientSayCommand_Post(int iClient, const char[] szChatType, const char[] szMessage)
{
  if (!DemoRec_IsRecording())
  {
    return;
  }

  StringMap hMap = new StringMap();
  UTIL_WriteClient(hMap, "client", iClient);
  hMap.SetString("text", szMessage);
  hMap.SetString("type", szChatType[3] == '_' ? "team" : "public");
  DemoRec_TriggerEvent("Core:ChatMessage", hMap);
  hMap.Close();
}

public void OnConfigsExecuted()
{
  OnRecordModeChanged(null, NULL_STRING, NULL_STRING);
  OnMinPlayersChanged(null, NULL_STRING, NULL_STRING);
}

/**
 * @section Custom event listeners
 */
public void OnEventTriggered(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
  bool bIsRoundStart = (!strcmp(szEventName, g_szRoundStartEvent, true)) && g_szRoundStartEvent[0];
  bool bIsRoundEnd = (!strcmp(szEventName, g_szRoundEndEvent, true))     && g_szRoundEndEvent[0];
  bool bIsRoundRelatedEvent = (bIsRoundStart || bIsRoundEnd);
  bool bIsRecording = DemoRec_IsRecording();

  if (bIsRoundRelatedEvent)
  {
    if (bIsRecording)
    {
      bIsRoundStart && DemoRec_TriggerEvent("Core:RoundStart", null, hEvent);
      bIsRoundEnd   && DemoRec_TriggerEvent("Core:RoundEnd", null, hEvent);
    }

    if (g_iRecordMode == 1)
    {
      bool bCheckResult = UTIL_CheckPlayers();
      if (bIsRoundStart && bIsRecording && !bCheckResult)
      {
        DemoRec_StopRecord();
        LogMessage("Recording stopped because required player count is not suit now");
      }
      else if (bIsRoundEnd && !bIsRecording && bCheckResult)
      {
        DemoRec_StartRecord();
        LogMessage("Recording started because required player count is received");
      }
    }

    if (!g_bRoundRecord || g_iRecordMode != 2)
    {
      return;
    }

    bIsRoundStart && !bIsRecording && DemoRec_StartRecord();
    bIsRoundEnd   &&  bIsRecording && DemoRec_StopRecord();
    return;
  }

  // Looks like this is kill event.
  if (!bIsRecording)
  {
    return;
  }

  if (!g_szKillClient[0] || !g_szKillVictim[0])
  {
    // If field names with client or victim is unknown - skip.
    return;
  }

  // Add event with kill.
  StringMap hEventDetails = new StringMap();
  UTIL_WriteClientFromEvent(hEventDetails, hEvent, "client", g_szKillClient);
  UTIL_WriteClientFromEvent(hEventDetails, hEvent, "victim", g_szKillVictim);

  DemoRec_TriggerEvent("Core:PlayerDeath", hEventDetails, hEvent);

  hEventDetails.Close();
}

public void OnMinPlayersChanged(ConVar hConVar, const char[] szOV, const char[] szNV)
{
  g_iMinPlayers = g_hMinPlayers.IntValue;
}

public void OnRecordModeChanged(ConVar hConVar, const char[] szOV, const char[] szNV)
{
  int iOldRecordMode = g_iRecordMode;
  g_iRecordMode = g_hRecordMode.IntValue;

  if (g_iRecordMode == iOldRecordMode)
  {
    return;
  }

  bool bIsRecording = DemoRec_IsRecording();
  if (g_iRecordMode == 0 && bIsRecording)
  {
    DemoRec_StopRecord();
    return;
  }

  if (g_iRecordMode == 1 && iOldRecordMode == 0 && !bIsRecording)
  {
    LogMessage("Waiting map change for start recording...");
    return;
  }

  if (g_iRecordMode == 2)
  {
    if (g_bRoundRecord)
    {
      LogMessage("Waiting new round for start recording...");
      return;
    }

    if (bIsRecording)
    {
      DemoRec_StopRecord();
    }

    LogError("Round record isn't supported. Rollback to disabled state.");
    g_hRecordMode.IntValue = 0;
    return;
  }
}

public Action DemoRec_OnClientPreRecordCheck(int iClient)
{
  return IsFakeClient(iClient) ?
    Plugin_Handled :
    Plugin_Continue;
}

/**
 * @section UTILs
 */
bool UTIL_CheckPlayers()
{
  if (g_iMinPlayers < 1)
  {
    return true;
  }

  return g_iMinPlayers <= UTIL_GetClientCount();
}

// Default GetClientCount() is not suit our requirements.
// So we implement own client counter.
int UTIL_GetClientCount(bool bInGameOnly = true, bool bWithSpectators = false)
{
  int iClients = 0;
  for (int iClient = MaxClients; iClient != 0; --iClient)
  {
    if (!IsClientConnected(iClient))
    {
      continue;
    }

    if (bInGameOnly == true && !IsClientInGame(iClient))
    {
      continue;
    }

    if (bWithSpectators == true && GetClientTeam(iClient) < 2) // 2 - red team (terrorists for CS, RED for TF2)
    {
      continue;
    }

    iClients++;
  }

  return iClients;
}

bool UTIL_GetEventName(Handle hGameConf, const char[] szEventName, char[] szBuffer, int iBufferLength)
{
  if (!UTIL_GetField(hGameConf, szEventName, szBuffer, iBufferLength))
  {
    LogError("Can't lookup engine event name %s.", szEventName);
    return false;
  }

  if (!HookEventEx(szBuffer, OnEventTriggered, EventHookMode_Post))
  {
    LogError("Can't hook engine event %s (internal name %s). Please ask gamedata update.", szEventName, szBuffer);
    return false;
  }

  return true;
}

bool UTIL_GetField(Handle hGameConf, const char[] szFieldName, char[] szBuffer, int iBufferLength)
{
  return GameConfGetKeyValue(hGameConf, szFieldName, szBuffer, iBufferLength);
}

void UTIL_WriteClientFromEvent(StringMap hMap, Event hEvent, const char[] szMapName, const char[] szEventName)
{
  int iClient = hEvent.GetInt(szEventName, 0);
  if (iClient)
  {
    iClient = GetClientOfUserId(iClient);
  }

  UTIL_WriteClient(hMap, szMapName, iClient);
}

void UTIL_WriteClient(StringMap hMap, const char[] szMapName, int iClient)
{
  int iAccountID = iClient ? GetSteamAccountID(iClient) : 0;

  char szAccountID[16];
  IntToString(iAccountID, szAccountID, sizeof(szAccountID));
  hMap.SetString(szMapName, szAccountID, true);
}
