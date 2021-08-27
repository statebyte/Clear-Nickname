#include <vip_core>
#include <clear_nickname>

public Action CN_OnFilterCheckPre(int iClient, char[] sOldName, char[] sNewName, int iCountKeys)
{
    if(VIP_IsClientVIP(iClient)) return Plugin_Continue;
}