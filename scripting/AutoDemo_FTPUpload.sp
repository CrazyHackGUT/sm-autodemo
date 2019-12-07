#include <sourcemod>
#include <AutoDemo>
#include <curl>
#include <bzip2>

#define SSL CURLUSESSL_NONE // CURLUSESSL_TRY

public Plugin myinfo = {
    version     = "1.0",
    author      = "Se7en",
    name        = "[AutoDemo] FTP Upload",
};

char g_szBaseDemoPath[PLATFORM_MAX_PATH];

Handle g_hFile;

ConVar g_hUploadHost;
ConVar g_hUploadPort;
ConVar g_hUploadUser;
ConVar g_hUploadPassword;
ConVar g_hUploadPath;

char g_sUploadHost[64];
int g_iUploadPort;
char g_sUploadUser[64];
char g_sUploadPassword[64];
char g_sUploadPath[64];

int CURL_Default_Opt[][2] = {
	{view_as<int>(CURLOPT_NOSIGNAL), 1},
	{view_as<int>(CURLOPT_NOPROGRESS), 1},
	{view_as<int>(CURLOPT_TIMEOUT), 90},
	{view_as<int>(CURLOPT_CONNECTTIMEOUT), 60},
	{view_as<int>(CURLOPT_VERBOSE), 0}
};

public void OnPluginStart()
{
	g_hUploadHost = CreateConVar("sm_demo_host", "", "Адрес FTP хоста"); 
	g_hUploadHost.GetString(g_sUploadHost, sizeof(g_sUploadHost));

	g_hUploadPort = CreateConVar("sm_demo_port", "21", "Порт FTP хоста");
	g_iUploadPort = g_hUploadPort.IntValue;

	g_hUploadUser = CreateConVar("sm_demo_user", "", "Пользователь FTP хоста");
	g_hUploadUser.GetString(g_sUploadUser, sizeof(g_sUploadUser));

	g_hUploadPassword = CreateConVar("sm_demo_password", "", "Пароль FTP хоста");
	g_hUploadPassword.GetString(g_sUploadPassword, sizeof(g_sUploadPassword));

	g_hUploadPath = CreateConVar("sm_demo_upload_dir", "/", "Директория загрузки демо через FTP"); 
	g_hUploadPath.GetString(g_sUploadPath, sizeof(g_sUploadPath));

	AutoExecConfig(true, "autodemo_upload");
}

public void OnAllPluginsLoaded() {
	BuildPath(Path_SM, g_szBaseDemoPath, sizeof(g_szBaseDemoPath), "data/demos/");
}

public void DemoRec_OnRecordStop(const char[] szDemoId)
{
	char szFileName[64];
	FormatEx(szFileName, sizeof(szFileName), "%s.dem", szDemoId);
	
	uploadFile(szFileName);
}

void uploadFile(const char[] sFile)
{
	char szFile[192];
	char szFileBz2[192];
	FormatEx(szFile, sizeof(szFile), "%s/%s", g_szBaseDemoPath, sFile);
	FormatEx(szFileBz2, sizeof(szFileBz2), "%s.bz2", szFile);

	Handle hTrie = CreateTrie();
	SetTrieString(hTrie, "name", sFile);
	SetTrieString(hTrie, "demo_file", szFile);
	SetTrieString(hTrie, "demo_file_bz2", szFileBz2);
	
	BZ2_CompressFile(szFile, szFileBz2, 10, BZ2CallBack, hTrie);
}

public int BZ2CallBack(BZ_Error iError, char[] sFileFullDir, char[] sFileOut, any hTrie)
{
	char sFileName[128];
	GetTrieString(hTrie, "name", sFileName, sizeof(sFileName));

	if(iError == BZ_OK) {
		char szBuffer[192];

		GetTrieString(hTrie, "demo_file", szBuffer, sizeof(szBuffer));
		DeleteFile(szBuffer);
		
		FormatEx(szBuffer, sizeof(szBuffer), "%s.bz2", sFileName);
		SetTrieString(hTrie, "name", szBuffer);
		
		UploadFtpFile(szBuffer, sFileOut, hTrie);
	} else {
		LogError("Cannot compress file %s", sFileName);
		CloseHandle(hTrie);
	}
}

stock void UploadFtpFile(char[] sFileNameOut, char[] sFileOut, Handle hTrie) 
{
	char sFtpURL[512];
	
	FormatEx(sFtpURL, 512, "ftp://%s:%s@%s:%i%s%s", g_sUploadUser, g_sUploadPassword, g_sUploadHost, g_iUploadPort, g_sUploadPath, sFileNameOut);

	Handle hCurl = curl_easy_init();

	curl_easy_setopt_int_array(hCurl, CURL_Default_Opt, sizeof(CURL_Default_Opt));
	g_hFile = OpenFile(sFileOut, "rb");

	curl_easy_setopt_int(hCurl, CURLOPT_UPLOAD, 1);
	curl_easy_setopt_function(hCurl, CURLOPT_READFUNCTION, ReadFunction);

	curl_easy_setopt_int(hCurl, CURLOPT_FTP_CREATE_MISSING_DIRS, CURLFTP_CREATE_DIR);

	curl_easy_setopt_int(hCurl, CURLOPT_USE_SSL, SSL);

	curl_easy_setopt_string(hCurl, CURLOPT_URL, sFtpURL);
	
	curl_easy_perform_thread(hCurl, OnUploadComplete, hTrie);
}

public int ReadFunction(Handle hCurl, int bytes, int nmemb)
{
	if((bytes*nmemb) < 1)
		return 0;

	if(IsEndOfFile(g_hFile))
		return 0;

	int iBytesToRead = bytes * nmemb;

	char[] items = new char[iBytesToRead];
	int iPos, iCell;
	
	while(iPos < iBytesToRead && ReadFileCell(g_hFile, iCell, 1) == 1) 
		items[iPos++] = iCell;

	curl_set_send_buffer(hCurl, items, iPos);

	return iPos;
}

public void OnUploadComplete(Handle hndl, CURLcode code, any hTrie) 
{
	CloseHandle(hndl);

	CloseHandle(g_hFile);
	g_hFile = INVALID_HANDLE;
	
	char szBuffer[192];
	GetTrieString(hTrie, "name", szBuffer, sizeof(szBuffer));

	if(code == CURLE_OK) {
		PrintToServer("File uploaded: %s", szBuffer);

		GetTrieString(hTrie, "demo_file_bz2", szBuffer, sizeof(szBuffer));
		DeleteFile(szBuffer);
	} else {
		LogError("Cannot upload file: %s", szBuffer);
	}
	
	CloseHandle(hTrie);
}