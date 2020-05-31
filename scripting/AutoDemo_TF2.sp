/**
 * AutoDemo Recorder - Team Fortress 2
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
#include <tf2_stocks>

public Plugin myinfo = {
    description = "Extend event handling for Team Fortress 2",
    version     = "1.0.1",
    author      = "CrazyHackGUT",
    name        = "[AutoDemo] Team Fortress 2",
    url         = "https://kruzya.me"
};

public APLRes AskPluginLoad2(Handle hMySelf, bool bLate, char[] szBuffer, int iBuffer)
{
    if (GetEngineVersion() != Engine_TF2)
    {
        strcopy(szBuffer, iBuffer, "This plugin targeted only in Team Fortress 2!");
        return APLRes_Failure;
    }

    return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
    DemoRec_AddEventListener("Core:PlayerDeath", HandleFakeDeaths);
}

public void OnPluginEnd()
{
    DemoRec_RemoveEventListener("Core:PlayerDeath", HandleFakeDeaths);
}

public bool HandleFakeDeaths(char[] szEventName, int iBufferLength, StringMap hEventDetails, Event &hEvent)
{
    hEventDetails.SetString("isFakeDeath", hEvent.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER ? "1" : "0");
    return true;
}