#if defined _clear_nickname_included
 #endinput
#endif
#define _clear_nickname_included

public SharedPlugin __pl_clear_nickname= 
{
	name = "ClearNickname",
	file = "clear_nickname.smx",
	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

/**
 *	Вызывается перед установкой нового никнейма для игрока
 *
 *	@param iClient				Индекс игрока.
 *	@param sOldName				Никнейм игрока до изменения
 *	@param sNewName		        Никнейм игрока после фильтра (unnamed - в никнейме были одни только ключи)
 *  @param iCountKeys           Кол-во найденных ключей в никнейме игрока
 *
 *	@return						Plugin_Stop или Plugin_Handled  - запретит изменение никнейма;
 								Plugin_Changed - разрешит изменение никнейма
 */
forward Action CN_OnFilterCheckPre(int iClient, char[] sOldName, char[] sNewName, int iCountKeys);