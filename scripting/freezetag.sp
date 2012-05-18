#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>
#include <sdkhooks>

#define FLUTTERSHY_MAX_HP 2000
#define FREEZE_DURATION 5000.0
#define FREEZE_IMMUNITY_TIME 0.0 // Not implemented
#define MAX_CLIENT_IDS MAXPLAYERS + 1

new original_ff_val
new original_disable_respawn_times_val
new original_scramble_teams_val
new original_teams_unbalance_val
new original_autobalance_val
new original_respawnwavetime_val

new Handle:ff_convar
new Handle:disable_respawn_times_convar
new Handle:scramble_teams_convar
new Handle:teams_unbalance_convar
new Handle:autobalance_convar
new Handle:respawnwavetime_convar

new bool:is_fluttershy[MAX_CLIENT_IDS]
new displayed_health[MAX_CLIENT_IDS] // Not totally necessary because it can be calculated from current_health,
                                     // but it avoids running the calculation on every frame
new current_health[MAX_CLIENT_IDS]
new bool:bypass_immunity[MAX_CLIENT_IDS]

public OnPluginStart()
{
    HookEvent("player_hurt", EventPlayerHurt)
    
    // Admin commands (currently not admin only for debugging)
    RegConsoleCmd("unfreeze", UnfreezePlayerCommand)
    RegConsoleCmd("flutts", MakeFluttershyCommand)
    RegConsoleCmd("unflutts", ClearFluttershyCommand)
    
    // Block team swapping
    RegConsoleCmd("jointeam", BlockCommandAll)
    RegConsoleCmd("joinclass", BlockCommandFluttershy)
    RegConsoleCmd("kill", BlockCommandFluttershy)
    RegConsoleCmd("spectate", BlockCommandAll)
    RegConsoleCmd("explode", BlockCommandFluttershy)
    
    
    ff_convar = FindConVar("mp_friendlyfire")
    disable_respawn_times_convar = FindConVar("mp_disable_respawn_times")
    scramble_teams_convar = FindConVar("mp_scrambleteams_auto")
    teams_unbalance_convar = FindConVar("mp_teams_unbalance_limit")
    autobalance_convar = FindConVar("mp_autoteambalance")
    respawnwavetime_convar = FindConVar("mp_respawnwavetime")
    
    original_ff_val = GetConVarInt(ff_convar)
    original_disable_respawn_times_val = GetConVarInt(disable_respawn_times_convar)
    original_scramble_teams_val = GetConVarInt(scramble_teams_convar)
    original_teams_unbalance_val = GetConVarInt(teams_unbalance_convar)
    original_autobalance_val = GetConVarInt(autobalance_convar)
    original_respawnwavetime_val = GetConVarInt(respawnwavetime_convar)
    
    SetConVarInt(ff_convar, 1)
    SetConVarInt(disable_respawn_times_convar, 1)
    SetConVarInt(scramble_teams_convar, 0)
    SetConVarInt(teams_unbalance_convar, 0)
    SetConVarInt(autobalance_convar, 0)
    SetConVarInt(respawnwavetime_convar, 0)
    
    // Initialize arrays
    for (new i = 1; i < MAX_CLIENT_IDS; i++)
    {
        is_fluttershy[i] = false
        bypass_immunity[i] = false
    }
    
    // Apply SDKHooks to all clients in the server when the plugin is loaded
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            OnClientPutInServer(i)
        }
    }
    
    
}

public OnPluginEnd()
{
    SetConVarInt(ff_convar, original_ff_val)
    SetConVarInt(disable_respawn_times_convar, original_disable_respawn_times_val)
    SetConVarInt(scramble_teams_convar, original_scramble_teams_val)
    SetConVarInt(teams_unbalance_convar, original_teams_unbalance_val)
    SetConVarInt(autobalance_convar, original_autobalance_val)
    SetConVarInt(respawnwavetime_convar, original_respawnwavetime_val)
}

public OnClientPutInServer(client)
{
    PrintToChatAll("%N connected.", client)
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage)
    SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost)
    SDKHook(client, SDKHook_WeaponCanSwitchTo, WeaponCanSwitchTo)
    SDKHook(client, SDKHook_WeaponCanUse, WeaponCanSwitchTo)
    SDKHook(client, SDKHook_Spawn, OnSpawn)
}

public Action:OnSpawn(client)
{
    if (!is_fluttershy[client] && GetClientTeam(client) != 2)
    {
        ChangeClientTeam(client, 2)
        TF2_RespawnPlayer(client)
    }
    else if (is_fluttershy[client] && GetClientTeam(client) != 3)
    {
        ChangeClientTeam(client, 3)
        TF2_RespawnPlayer(client)
    }
    
    return Plugin_Continue
}

public Action:WeaponCanSwitchTo(client, weapon)
{
    if (GetPlayerWeaponSlot(client, 2) < 0 || weapon == GetPlayerWeaponSlot(client, 2))
        return Plugin_Continue
    else
        return Plugin_Handled
}

public OnGameFrame()
{
    // This reverses the health degeneration of the Fluttershys
    for (new i = 0; i < sizeof(is_fluttershy); i++)
    {
        if (is_fluttershy[i])
            SetEntityHealth(i, displayed_health[i])
    }
}

public Action:EventPlayerHurt(Handle:event, const String:name[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    
    // Restore self-inflicted damage. For some reason regenerating self damage works in this event
    // handler, but restoring deadly enemy damage will not. Self damage is enabled on Fluttershys for
    // testing purposes
    if (!is_fluttershy[client])
        SetEntityHealth(client, GetClientHealth(client) + GetEventInt(event, "damageamount"))
    
    return Plugin_Continue
}

public OnTakeDamagePost(victim, attacker, inflictor, Float:damage, damagetype, weapon, const Float:damageForce[3], const Float:damagePosition[3])
{
    // The player is supposed to die, do not modify damage
    if (bypass_immunity[victim])
    {
        bypass_immunity[victim] = false
    }
    else if (is_fluttershy[victim] && !IsWorldDeath(attacker))
    {
        current_health[victim] = current_health[victim] - RoundFloat(damage)
        
        if (current_health[victim] <= 0)
        {
            PrintToChatAll("%N has defeated %N!", attacker, victim)
            ClearFluttershy(victim, attacker)
        }
        else
        {
            displayed_health[victim] = displayed_health[victim] - RoundFloat(damage)
            
            // Refill the life bar and display to the user the multiple of 1000 that his life is now counting down from
            if (displayed_health[victim] <= 0)
            {
                PrintToChat(victim, "Current Health: %d", current_health[victim]);
                displayed_health[victim] = current_health[victim] - ((current_health[victim] / 1000) * 1000)
            }
            
        
            SetEntityHealth(victim, displayed_health[victim])
        }
    }
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype, &weapon, Float:damageForce[3], Float:damagePosition[3])
{    
    // The player is supposed to die, don't modify damage but remove the gib effect that happens
    // due to using an explosive entity to kill the player
    if (bypass_immunity[victim])
    {
        damagetype = damagetype | _:DMG_NEVERGIB & _:(!DMG_ALWAYSGIB)
        return Plugin_Changed
    }
    
    // Respawn players that fall off the map instantly since they cannot die to the fall damage
    if (IsWorldDeath(attacker))
    {
        TF2_RespawnPlayer(victim)
        return Plugin_Handled
    }
        
    if (is_fluttershy[victim])
    {
        // Damage doesn't get modified by crits or distance until after OnTakeDamage has run
        // Since we need to wait for OnTakeDamage to complete, set the player's health 
        // very high to prevent them from dying during OnTakeDamage. We will force the player
        // to die later if necessary
        SetEntityHealth(victim, 3000)
        return Plugin_Continue
    }
        
    // If enemy is hit and not frozen, freeze him. Damage done by the environment can never freeze a player.
    if (attacker != 0 && GetClientTeam(victim) != GetClientTeam(attacker) && !TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        FreezePlayer(victim, attacker)
    }
    // If ally is hit and frozen, unfreeze him
    else if (attacker != 0 && GetClientTeam(victim) == GetClientTeam(attacker) && TF2_IsPlayerInCondition(victim, TFCond_Dazed))
    {
        UnfreezePlayer(victim, attacker)
    }
    
    // If damage was self-inflicted, do not reduce it since it impairs the ability to rocket jump
    // (Game mode is melee only for now, but that could change)
    if (attacker == victim)
    {
        return Plugin_Continue
    }
    // Remove all other damage. This prevents all damage related pushback.
    else
    {
        damage = 0.0
        return Plugin_Changed
    }
}

bool:IsWorldDeath(attacker)
{
    return attacker == 107
}

FreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH]
    decl String:attacker_name[MAX_NAME_LENGTH]
    GetCustomClientName(victim, victim_name, sizeof(victim_name))
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name))
    
    PrintToChatAll("%s frozen by %s.", victim_name, attacker_name)
    TF2_StunPlayer(victim, FREEZE_DURATION, 0.0, TF_STUNFLAG_BONKSTUCK, attacker)
}

UnfreezePlayer(victim, attacker)
{
    decl String:victim_name[MAX_NAME_LENGTH]
    decl String:attacker_name[MAX_NAME_LENGTH]
    GetCustomClientName(victim, victim_name, sizeof(victim_name))
    GetCustomClientName(attacker, attacker_name, sizeof(attacker_name))
    
    PrintToChatAll("%s has been unfrozen by %s!", victim_name, attacker_name)
    TF2_RemoveCondition(victim, TFCond_Dazed)
}

GetCustomClientName(client, String:name[], length)
{
    if (client < 1)
        strcopy(name, length, "The Guardians")
    else
        GetClientName(client, name, length)
}

// Handle debug/admin unfreeze command
public Action:UnfreezePlayerCommand(client, args)
{
    UnfreezePlayer(client, 0)
}

// Handle debug/admin flutts command
public Action:MakeFluttershyCommand(client, args)
{
    decl String:text[MAX_NAME_LENGTH]
    decl String:name[MAX_NAME_LENGTH]
    decl String:user_id[16]
    
    if (args < 1)
    {
        new Handle:menu = CreateMenu(MakeFluttershyMenuHandler)
        SetMenuTitle(menu, "Select a player:")
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name))
                IntToString(GetClientUserId(i), user_id, sizeof(user_id))
                AddMenuItem(menu, user_id, name)
            }
        }
        
        SetMenuExitButton(menu, true);
        DisplayMenu(menu, client, 20);
        
        return Plugin_Handled
    }
    else 
    { 
        GetCmdArgString(text, sizeof(text))
     
        new startidx = 0
        if (text[0] == '"')
        {
            startidx = 1
            /* Strip the ending quote, if there is one */
            new len = strlen(text);
            if (text[len-1] == '"')
            {
                text[len-1] = '\0'
            }
        }
        
        new target = -1
        
        for (new i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i))
            {
                GetClientName(i, name, sizeof(name))
                if (StrContains(name, text[startidx], false) > -1)
                {
                    if (target != -1)
                    {
                        ReplyToCommand(client, "Ambiguous player name '%s'.", text[startidx])
                        return Plugin_Handled
                    }
                    else
                    {
                        target = i
                    }
                }
            }
        }
        if (target > 0)
            MakeFluttershy(target)
        else
            ReplyToCommand(client, "Could not find player '%s'.", text[startidx])
        return Plugin_Handled
    }
}

SelectPlayer(client, MenuHandler:handler, String:search_name[])
{
}

// Handle debug/admin unflutts command
public Action:ClearFluttershyCommand(client, args)
{
    PrintToChatAll("The Guardians have rescinded %N's Flutterhood!", client)
    ClearFluttershy(client, 0)
}

public MakeFluttershyMenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
    decl String:info[32]

    if (action == MenuAction_Select)
    {
        GetMenuItem(menu, param2, info, sizeof(info))
        new target = GetClientOfUserId(StringToInt(info))
        if (IsClientInGame(target))
        MakeFluttershy(target)
    }
    else if (action == MenuAction_End)
    {
        CloseHandle(menu)
    }
}

MakeFluttershy(client)
{
    PrintToChatAll("%N is now a Fluttershy.", client)
    TF2_SetPlayerClass(client, TFClass_Medic);
    is_fluttershy[client] = true
    ChangeClientTeam(client, 3)
    TF2_RespawnPlayer(client)
#if FLUTTERSHY_MAX_HP < 1000
    displayed_health[client] = FLUTTERSHY_MAX_HP
#else
    displayed_health[client] = 1000
#endif
    current_health[client] = FLUTTERSHY_MAX_HP
    SetEntityHealth(client, displayed_health[client])
}

ClearFluttershy(client, attacker)
{
    is_fluttershy[client] = false
    bypass_immunity[client] = true
    KillPlayer(client, attacker)
    ChangeClientTeam(client, 2)
    TF2_RespawnPlayer(client)
}

// From pheadxdll's Roll the Dice mod (http://forums.alliedmods.net/showthread.php?t=75561)
// Modified by Dr. McKay (http://forums.alliedmods.net/showthread.php?p=1710929)
KillPlayer(client, attacker) 
{ 
    new ent = CreateEntityByName("env_explosion"); 
     
    if (IsValidEntity(ent)) 
    { 
        DispatchKeyValue(ent, "iMagnitude", "5000"); 
        DispatchKeyValue(ent, "iRadiusOverride", "2"); 
        SetEntPropEnt(ent, Prop_Data, "m_hInflictor", attacker); 
        SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", attacker); 
        DispatchKeyValue(ent, "spawnflags", "3964"); 
        DispatchSpawn(ent); 
         
        new Float:pos[3]; 
        GetClientAbsOrigin(client, pos); 
        TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR); 
        AcceptEntityInput(ent, "explode", client, client); 
        CreateTimer(0.2, RemoveExplosion, ent); 
    } 
} 

// From pheadxdll's Roll the Dice mod (http://forums.alliedmods.net/showthread.php?t=75561)
// Modified by Dr. McKay (http://forums.alliedmods.net/showthread.php?p=1710929)
public Action:RemoveExplosion(Handle:timer, any:ent) 
{ 
    if (IsValidEntity(ent)) 
    { 
        decl String:edictname[128]; 
        GetEdictClassname(ent, edictname, 128); 
        if(StrEqual(edictname, "env_explosion")) 
        { 
            RemoveEdict(ent); 
        } 
    } 
}  

public Action:BlockCommandAll(client, args)
{
    return Plugin_Handled
}

public Action:BlockCommandFluttershy(client, args)
{
    if (is_fluttershy[client])
        return Plugin_Handled
    else
        return Plugin_Continue
}