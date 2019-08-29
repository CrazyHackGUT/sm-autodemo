/**
 * AutoDemo Recorder - Chat Notifications
 * Copyright (C) 2019 CrazyHackGUT aka Kruzya
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
#include <AutoDemo>

public Plugin myinfo = {
    description = "Adds a notifications in chat about demo status",
    version     = "1.0",
    author      = "CrazyHackGUT aka Kruzya",
    name        = "[AutoDemo] Notifications",
    url         = "https://kruzya.me"
};

public void OnPluginStart()
{
    LoadTranslations("autodemo_notifications.phrases");
}

public void DemoRec_OnRecordStart(const char[] szDemoId)
{
    UTIL_PrintToChat("RecordStart", szDemoId);
}

public void DemoRec_OnRecordStop(const char[] szDemoId)
{
    UTIL_PrintToChat("RecordStop", szDemoId);
}

void UTIL_PrintToChat(const char[] szPhrase, const char[] szDemoId)
{
    PrintToChatAll("%t", szPhrase, szDemoId);
}