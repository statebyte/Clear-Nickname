#include <sourcemod>
#include <sdktools_functions>
#include <adminmenu>

#define CONFIG_REPLACE_PATH "configs/clear_nickname/clear_nickname.ini"
#define DEFAULT_NULL_NICKNAME "unnamed"

#define DB_NAMESECTION "clear_nickname"
#define DB_TABLENAME "clear_nickname"

#define RECURSIVE_SEARCH 0 // Вкл/выкл рекурсивный поиск (ПОВТОРЯЮЩИЕСЯ КЛЮЧИ)
#define SENSETIVE false // Чуствительно ли к регистру?
#define CHECK_NICKNAMESPAM 1 // Проверять на наличиее спама от игроков
#define COUNT_OF_SECONDS 5
#define COUNT_OF_CHANGES 5
#define NICKNAME_COUNT 64

char g_sLogPath[PLATFORM_MAX_PATH];
ArrayList g_hReplaceKeys;
TopMenu g_hTopMenu = null;
bool g_bHookMsg[MAXPLAYERS+1], g_bDB;
Database g_hDatabase;
Handle g_hGFwd_OnFilterCheckPre;

public Plugin myinfo =
{
	name	=	"Clear Nickname",
	author	=	"FIVE, Domikuss",
	version	=	"1.1.0",
	url		=	"https://hlmod.ru"
};

public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] szError, int iErr_max)
{
	g_hGFwd_OnFilterCheckPre = CreateGlobalForward("CN_OnFilterCheckPre", ET_Hook, Param_Cell, Param_String, Param_String, Param_Cell);

	RegPluginLibrary("ClearNickname");
	
	return APLRes_Success;
}

Action CallForward_OnFilterCheckPre(int iClient, char[] sOldName, char[] sNewName, int iCount)
{
	Action Result = Plugin_Changed;
	Call_StartForward(g_hGFwd_OnFilterCheckPre);
	Call_PushCell(iClient);
	Call_PushString(sOldName);
	Call_PushString(sNewName);
	Call_PushCell(iCount);
	Call_Finish(Result);
	return Result;
}

public void OnPluginStart()
{
	LoadTranslations("clear_nickname.phrases");

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "logs/clear_nickname");
	if(!DirExists(sPath)) CreateDirectory(sPath, 511);

	char szBuffer[256];
	FormatTime(szBuffer, sizeof(szBuffer), "%F", GetTime());
	BuildPath(Path_SM, g_sLogPath, sizeof(g_sLogPath), "logs/clear_nickname/log_%s.log", szBuffer);
	
	g_hReplaceKeys = new ArrayList(ByteCountToCells(NICKNAME_COUNT));

	LoadDatabase();
	HookEventEx("player_changename", Event_NameChanged, EventHookMode_Pre);

	RegConsoleCmd("sm_clearname", cmd_ClearName);
	RegConsoleCmd("sm_clearname_export", cmd_ClearNameExport);
	RegConsoleCmd("sm_clearname_reload", cmd_ClearNameReload);

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say2");
	AddCommandListener(Command_Say, "say_team");

	if(LibraryExists("adminmenu"))
	{
		TopMenu hTopMenu;
		if((hTopMenu = GetAdminTopMenu()) != null) // Если админ-меню уже создано
		{
			// Вызываем ф-ю, в которой добавляется пункт в админ-меню
			OnAdminMenuReady(hTopMenu);
		}
	}
}

Action cmd_ClearNameExport(int iClient, int iArgs)
{
	if(g_bDB)
	{
		char sPath[PLATFORM_MAX_PATH], szBuffer[256];
		BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_REPLACE_PATH);

		PrintToServer(sPath);

		if(FileExists(sPath))
		{
			File hFile = OpenFile(sPath, "r", false);

			if(hFile != null)
			{
				Transaction hTxn = new Transaction();
				
				int icount;
				while(!hFile.EndOfFile() && hFile.ReadLine(szBuffer, sizeof(szBuffer)))
				{
					TrimString(szBuffer);
					char sQuery[128];
					
					g_hDatabase.Format(sQuery, sizeof sQuery, "INSERT INTO %s SET `key_word` = '%s', `account_id` = %i", DB_TABLENAME, szBuffer, iClient == 0 ? 0 : GetSteamAccountID(iClient));
					hTxn.AddQuery(sQuery);
					icount++;
				}

				g_hDatabase.Execute(hTxn, SQL_TxnCallback_Success, SQL_TxnCallback_Failure, icount);

				PrintToServer("[clear_nickname] Export: Success loaded - %i keys", icount);

				delete hFile;
			}
			else PrintToServer("[clear_nickname] Export: File don't open");
		}
		else PrintToServer("[clear_nickname] Export: File for export not found");
	}
	else PrintToServer("[clear_nickname] Export: DB not enabled");
	

	return Plugin_Handled;
}

void SQL_TxnCallback_Success(Database hDatabase, any Data, int iNumQueries, DBResultSet[] results, any[] QueryData)
{
	PrintToServer("[clear_nickname] Export: Success export to DB");
}

void SQL_TxnCallback_Failure(Database hDatabase, any Data, int iNumQueries, const char[] szError, int iFailIndex, any[] QueryData)
{
	LogError("SQL_TxnCallback_Failure: %s", szError);
}

void LoadDatabase()
{
	if(SQL_CheckConfig(DB_NAMESECTION))
	{
		g_bDB = true;
		Database.Connect(ConnectCallBack, DB_NAMESECTION);
	}
	else
	{
		g_bDB = false;
		LoadConfig();
	}
}

void ConnectCallBack(Database hDB, const char[] szError, any data) // Пришел результат соединения
{
	if(hDB == null || szError[0]) // Соединение не удачное
	{
		SetFailState("Database failure: %s", szError); // Отключаем плагин
		return;
	}

	g_hDatabase = hDB;
	g_hDatabase.SetCharset("utf8mb4");

	DB_CreateTables();
	LoadConfig();
}

void DB_CreateTables()
{
	static bool bCrateTables;
	if(!bCrateTables)
	{
		bCrateTables = true;

		char sQuery[1024];
		g_hDatabase.Format(sQuery, sizeof sQuery, "CREATE TABLE IF NOT EXISTS `%s` ( \
				`id` int(11) NOT NULL AUTO_INCREMENT, \
				`key_word` varchar(64) NOT NULL UNIQUE, \
				`account_id` int(11) DEFAULT 0, \
				PRIMARY KEY (`id`) \
			) ENGINE = InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;", DB_TABLENAME);
		g_hDatabase.Query(SQL_Callback_CreateTables, sQuery);
	}
}

bool DB_CheckDatabaseConnection(const char[] sError, const char[] szErrorTag)
{
	if(!g_hDatabase || !strcmp(sError, "Lost connection to MySQL server"))
	{
		LogError("%s: %s", szErrorTag, sError);
		delete g_hDatabase;
		LoadDatabase();
		return false;
	}
	return true;
}

void DB_LoadKeys()
{
	char sQuery[128];
	g_hDatabase.Format(sQuery, sizeof sQuery, "SELECT `key_word` FROM %s", DB_TABLENAME);
	g_hDatabase.Query(SQL_Callback_LoadKeys, sQuery);
}

void SQL_Default_Callback(Database hDatabase, DBResultSet hResult, const char[] sError, any QueryID)
{
	if(!DB_CheckDatabaseConnection(sError, "SQL_Callback_CreateTables"))
	{
		return;
	}
}

void SQL_Callback_CreateTables(Database hDatabase, DBResultSet hResult, const char[] sError, any data)
{
	if(!DB_CheckDatabaseConnection(sError, "SQL_Callback_CreateTables"))
	{
		g_hDatabase.Query(SQL_Default_Callback, "SET NAMES 'utf8mb4'", 1);
		g_hDatabase.Query(SQL_Default_Callback, "SET CHARSET 'utf8mb4'", 2);
	}
}

void SQL_Callback_LoadKeys(Database hDatabase, DBResultSet hResult, const char[] sError, any QueryID)
{
	if(!DB_CheckDatabaseConnection(sError, "SQL_Callback_LoadKeys"))
	{
		return;
	}

	char szBuffer[256];

	while(hResult.FetchRow())
	{
		hResult.FetchString(0, szBuffer, sizeof(szBuffer));
		g_hReplaceKeys.PushString(szBuffer);
	}

	PrintToServer("[clear_nickname] Loaded %i keys - OK", g_hReplaceKeys.Length);

	for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
	{
		OnClientPutInServer(i);
	}
}

Action Command_Say(int iClient, const char[] sCommand, int iArgs)
{
	char sValue[32];
	SetGlobalTransTarget(iClient);
	
	if(g_bHookMsg[iClient])
	{
		GetCmdArg(1, sValue, sizeof(sValue));
		AddKey(sValue, iClient);
		g_bHookMsg[iClient] = false;
		OpenMenu(iClient);

		LogToFile(g_sLogPath, "%T", "AdminKeyAdded", LANG_SERVER, iClient, sValue);
		PrintToChat(iClient, "%t%t", "ChatPrefix", "KeyAdded", sValue);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public void OnLibraryRemoved(const char[] szName)
{
	if(!strcmp(szName, "adminmenu"))
	{
		g_hTopMenu = null;
	}
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu hTopMenu = TopMenu.FromHandle(aTopMenu);

	if(hTopMenu == g_hTopMenu)
	{
		return;
	}

	g_hTopMenu = hTopMenu;

	TopMenuObject hMyCategory = g_hTopMenu.FindCategory("PlayerCommands");

	if(hMyCategory != INVALID_TOPMENUOBJECT)
	{
		g_hTopMenu.AddItem("clearname", Handler_MenuClearName, hMyCategory, "sm_clearname_menu", ADMFLAG_SLAY, "Проверка ника на рекламу");
	}
}

void Handler_MenuClearName(TopMenu hMenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch (action)
	{
		case TopMenuAction_DisplayOption: FormatEx(sBuffer, maxlength, "%T", "CheckAdvert", iClient);
		case TopMenuAction_SelectOption: OpenMenu(iClient);
	}
}

void OpenMenu(int iClient)
{
	char szBuffer[256];
	Menu hMenu = new Menu(MenuHandler_MyMenu);
	hMenu.ExitBackButton = true;
	SetGlobalTransTarget(iClient);

	hMenu.SetTitle("%t\n \n", "CheckAdvert");
	FormatEx(szBuffer, sizeof(szBuffer), "%t", "AddSite");
	hMenu.AddItem(NULL_STRING, szBuffer);
	FormatEx(szBuffer, sizeof(szBuffer), "%t", "RefreshList");
	hMenu.AddItem(NULL_STRING, szBuffer);
	FormatEx(szBuffer, sizeof(szBuffer), "%t\n \n", "ReloadConfig");
	hMenu.AddItem(NULL_STRING, szBuffer);

	char sBuffer[4], sName[NICKNAME_COUNT], sNewName[NICKNAME_COUNT];
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			GetClientName(i, sName, sizeof(sName));
			IntToString(i, sBuffer, sizeof(sBuffer));
			strcopy(sNewName, sizeof(sNewName), sName);

			if(CheckClientName(sNewName, sizeof(sNewName)) == 0)
			{
				FormatEx(sName, sizeof(sName), "%N [%t]", i, "NoAdvert");
				hMenu.AddItem(sBuffer, sName, ITEMDRAW_DISABLED);
			}
			else
			{
				hMenu.AddItem(sBuffer, sName, ITEMDRAW_DEFAULT);
			}
		}
	}
	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

int MenuHandler_MyMenu(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				RedisplayAdminMenu(g_hTopMenu, iClient);
			}
		}
		case MenuAction_Select:
		{
			switch(iItem)
			{
				case 0:
				{
					HookMsg(iClient);
				}
				case 1:
				{
					OpenMenu(iClient);
				}
				case 2:
				{
					LoadConfig();
					PrintToChat(iClient, "%t%t", "ChatPrefix", "ConfigReloaded");
					OpenMenu(iClient);
				}
				default:
				{
					#define iTarget iItem

					static char szInfo[4];
					static char sName[NICKNAME_COUNT];
					static char sOldName[NICKNAME_COUNT];

					hMenu.GetItem(iItem, szInfo, sizeof(szInfo));

					iTarget = StringToInt(szInfo);

					GetClientName(iTarget, sName, sizeof(sName));
					sOldName = sName;

					int iCountKey = CheckClientName(sName, sizeof(sName));

					if(iCountKey > 0)
					{
						Action Result = CallForward_OnFilterCheckPre(iClient, sOldName, sName, iCountKey);

						if(Result == Plugin_Changed)
						{
							SetGlobalTransTarget(iClient);
							SetClientName(iTarget, sName);
							PrintToChat(iClient, "%t%t", "ChatPrefix", "NicknameChanged", sOldName, sName, iCountKey);
							LogToFile(g_sLogPath, "%T", "NicknameChanged", LANG_SERVER, sOldName, sName, iCountKey);
						}
					}

					OpenMenu(iClient);
				}
			}
		}
	}

	return 0;
}

void HookMsg(int iClient)
{
	g_bHookMsg[iClient] = true;
	
	char szBuffer[128];

	Menu hMenu = new Menu(Handler_HookMenu);

	hMenu.SetTitle("%t\n \n", "AddSite");
	
	FormatEx(szBuffer, sizeof(szBuffer), "%t", "MenuDescription");
	hMenu.AddItem(NULL_STRING, szBuffer, ITEMDRAW_DISABLED);

	hMenu.ExitButton = true;
	hMenu.ExitBackButton = true;
	hMenu.Display(iClient, MENU_TIME_FOREVER);
}

int Handler_HookMenu(Menu hMenu, MenuAction action, int iClient, int iItem)
{
	switch(action)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel:
		{
			if(iItem == MenuCancel_ExitBack)
			{
				OpenMenu(iClient);
			}
			g_bHookMsg[iClient] = false;
		}
	}
	
	return 0;
}

Action cmd_ClearName(int iClient, int iArgs)
{
	SetGlobalTransTarget(iClient);
	if(iClient > 0)
	{
		char sName[NICKNAME_COUNT];
		GetClientName(iClient, sName, sizeof(sName));
	
		int iCountKey = CheckClientName(sName, sizeof(sName));
		if(iCountKey > 0)
		{
			SetClientName(iClient, sName);
			PrintToChat(iClient, "%t%t", "ChatPrefix", "AdvertFound", iCountKey);
		}
		else PrintToChat(iClient, "%t%t", "ChatPrefix", "NotFound");
	}

	return Plugin_Handled;
}

Action cmd_ClearNameReload(int iClient, int iArgs)
{
	PrintToConsole(iClient, "%t", "ConfigReloaded");
	LoadConfig();

	return Plugin_Handled;
}

void LoadConfig()
{
	if(g_hReplaceKeys) g_hReplaceKeys.Clear();
	
	if(g_bDB)
	{
		DB_LoadKeys();
	}
	else 
	{
		char sPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_REPLACE_PATH);

		if(FileExists(sPath))
		{
			File hFile = OpenFile(sPath, "r", false);

			if(hFile != null)
			{
				char szBuffer[256];

				while(!hFile.EndOfFile() && hFile.ReadLine(szBuffer, sizeof(szBuffer))) 
				{
					TrimString(szBuffer);
					g_hReplaceKeys.PushString(szBuffer);
				}

				delete hFile;
			}

			PrintToServer("[clear_nickname] Loaded %i keys - OK", g_hReplaceKeys.Length);
		}

		for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int iClient)
{
	char sName[NICKNAME_COUNT], sOldName[NICKNAME_COUNT];

	GetClientName(iClient, sName, sizeof(sName));

	sOldName = sName;
	
	int iCountKey = CheckClientName(sName, sizeof(sName));

	if(iCountKey > 0)
	{
		SetClientName(iClient, sName);
		LogToFile(g_sLogPath, "%T", "NicknameChanged", LANG_SERVER, sOldName, sName, iCountKey);
	}
}

Action Event_NameChanged(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(event.GetInt("userid"));

	SetGlobalTransTarget(iClient);

	char sNewName[NICKNAME_COUNT], sOldName[NICKNAME_COUNT];
	event.GetString("newname", sNewName, sizeof(sNewName));
	event.GetString("oldname", sOldName, sizeof(sOldName));

	// Защита от спама игроков
	#if CHECK_NICKNAMESPAM == 1
	{
		static int iTime[MAXPLAYERS+1], iCount[MAXPLAYERS+1];
		//PrintToChatAll("CHECK %i %i", iTime[iClient], iCount[iClient]);
		if(iTime[iClient] >= GetTime())
		{
			//PrintToChatAll("CHECK NAMI %i", iCount[iClient]);
			if(iCount[iClient] >= COUNT_OF_CHANGES) 
			{
				LogToFile(g_sLogPath, "[clear_nickname] Spam Nickname Change %L", iClient);
				KickClient(iClient, "SPAM NICKNAME");
				return Plugin_Handled;
			}

			iCount[iClient]++;
		}
		else 
		{
			//PrintToChatAll("CHECK NAMI CLEAR");
			iCount[iClient] = 0;
			iTime[iClient] = GetTime() + COUNT_OF_SECONDS;
		}
	}
	#endif
	

	int iCountKey = CheckClientName(sNewName, sizeof(sNewName));

	if(iCountKey > 0)
	{
		Action Result = CallForward_OnFilterCheckPre(iClient, sOldName, sNewName, iCountKey);

		if(Result == Plugin_Changed)
		{
			PrintToChat(iClient, "%t%t", "ChatPrefix", "AutoAdvertFound", iCountKey);
			LogToFile(g_sLogPath, "%T", "AutoAdvertFound", LANG_SERVER, sOldName, sNewName, iCountKey);
			SetClientName(iClient, sNewName);
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

void AddKey(char[] sKey, int iClient = 0)
{
	TrimString(sKey);
	
	if(g_bDB)
	{
		g_hReplaceKeys.PushString(sKey);
		
		char sQuery[128];
		g_hDatabase.Format(sQuery, sizeof sQuery, "INSERT INTO %s SET `key_word` = '%s', `account_id` = %i", DB_TABLENAME, sKey, iClient == 0 ? 0 : GetSteamAccountID(iClient));
		g_hDatabase.Query(SQL_Default_Callback, sQuery);
	}
	else 
	{
		char sPath[PLATFORM_MAX_PATH];
		BuildPath(Path_SM, sPath, sizeof(sPath), CONFIG_REPLACE_PATH);

		if(FileExists(sPath))
		{
			File hFile = OpenFile(sPath, "a+", false);

			if(hFile != null)
			{
				hFile.WriteLine(sKey);
				g_hReplaceKeys.PushString(sKey);

				delete hFile;
			}
		}
	}

	PrintToServer("[clear_nickname] Add key [%s]. Save %i keys - OK", sKey, g_hReplaceKeys.Length);
}

int CheckClientName(char[] sNewName, int iMaxLen)
{
	int iCountKeys = 0;
	char sKey[NICKNAME_COUNT], szBuffer[2][NICKNAME_COUNT];

	for(int i = 0, iSize = g_hReplaceKeys.Length, iLen, iPos; i < iSize; i++)
	{
		g_hReplaceKeys.GetString(i, sKey, sizeof(sKey));
		iLen = strlen(sKey);

		iPos = StrContains(sNewName, sKey, SENSETIVE);
		if(iPos != -1)
		{
			strcopy(szBuffer[1], sizeof(szBuffer[]), sNewName[iPos + iLen]);
			sNewName[iPos] = EOS;
			FormatEx(szBuffer[0], sizeof(szBuffer[]), "%s%s", sNewName, szBuffer[1]);
			strcopy( sNewName, iMaxLen, szBuffer[0]);
			iCountKeys++;
		}
	}

	TrimString(sNewName);

	if(!strcmp(sNewName, ""))
	{
		strcopy(sNewName, iMaxLen, DEFAULT_NULL_NICKNAME);
	}

	#if RECURSIVE_SEARCH 1
	// Если было найдены ключ и из-за смещения ключ был не определён.
	if(iCountKeys > 0)
	{
		iCountKeys += CheckClientName(sNewName, iMaxLen);
	}
	#endif

	return iCountKeys;
}