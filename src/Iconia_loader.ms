-- ------------------------------------------------------
-- Iconia Loader (Startup Script)
-- Charge le menu et verifie silencieusement les updates
-- ------------------------------------------------------

(
    -- 1. Chargement du Menu (3ds Max 2026+)
    try (
        local menuPath = "C:\\Users\\" + sysInfo.username + "\\Autodesk\\3ds Max 2026\\User Settings\\Iconia.mnx"
        local envVar = "ADSK_3DSMAX_CUI_PRE_USER_CONFIG_2026"
        
        -- On récupère les menus potentiellement déjà chargés par d'autres scripts
        local existingMenus = systemTools.getEnvVariable envVar
        
        if existingMenus == undefined or existingMenus == "" then (
            -- S'il n'y a rien, on assigne simplement notre menu
            systemTools.setEnvVariable envVar menuPath
        ) else (
            -- Si d'autres menus existent, on vérifie qu'on ne fait pas de doublon
            if matchPattern existingMenus pattern:("*" + menuPath + "*") == false then (
                -- On ajoute notre menu à la liste existante, séparé par un point-virgule
                systemTools.setEnvVariable envVar (existingMenus + ";" + menuPath)
            )
        )

        local menuMgr = maxops.GetICuiMenuMgr()
        menuMgr.LoadConfiguration(menuMgr.GetCurrentConfiguration())
        print "Iconia menu loaded..."
    ) catch (
        format "Iconia Loader Error (Menu) : %\n" (getCurrentException())
    )

    -- --------------------------------------------------
    -- 2. Verification silencieuse des mises a jour
    -- --------------------------------------------------
    
    -- Comparaison Mathématique Réelle (SemVer)
    fn isNewerVersion remote localStr = (
        local rArr = filterString remote ".vV \t\r\n"
        local lArr = filterString localStr ".vV \t\r\n"
        local maxLen = amax rArr.count lArr.count
        
        for i = 1 to maxLen do (
            local rVal = if i <= rArr.count then (rArr[i] as integer) else 0
            local lVal = if i <= lArr.count then (lArr[i] as integer) else 0
            if rVal > lVal do return true  
            if rVal < lVal do return false 
        )
        return false 
    )

    -- Source des mises a jour : partage LAN (UNC pour ne pas dependre de L:)
    local updateRoot        = "\\\\CgLibrary\\CgLibrary\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\Iconia\\"
    local remoteVersionFile = updateRoot + "version.txt"
    local remoteMZPFile     = updateRoot + "Iconia.mzp"

    -- Version locale
    local root        = (getDir #userScripts) + "\\Iconia"
    local versionFile = root + "\\version.txt"
    local localVer    = "0.0.0"

    if doesFileExist versionFile then (
        local f = openFile versionFile mode:"r"
        localVer = trimRight (readLine f)
        close f
    )

    -- Check en arriere-plan
    try (
        local remoteVer = ""
        if doesFileExist remoteVersionFile then (
            local remoteFile = openFile remoteVersionFile mode:"r"
            remoteVer = trimRight (readLine remoteFile)
            close remoteFile
        )

        -- Si on trouve une mise a jour, on propose a l'utilisateur
        if (remoteVer != "") and (isNewerVersion remoteVer localVer) then (
            local msg = "Une nouvelle version du menu Iconia (v" + remoteVer + ") est disponible !\n(Version actuelle : " + localVer + ")\n\nVoulez-vous la telecharger et l'installer maintenant ?"
            
            -- queryBox pose la question. Si l'utilisateur clique "Oui", ca lance l'update.
            if (queryBox msg title:"Mise a jour Iconia" beep:true) then (
                print "Copie de la mise a jour Iconia depuis le LAN..."
                
                local tempDir  = getDir #temp
                local mzpPath  = tempDir + "\\Iconia_update.mzp"
                if doesFileExist mzpPath do deleteFile mzpPath
                copyFile remoteMZPFile mzpPath

                if doesFileExist mzpPath then (
                    fileIn mzpPath
                    -- Le message de succes du fileIn prendra le relais
                ) else (
                    messageBox ("Echec de la copie depuis le partage LAN.\nVerifiez l'acces a :\n" + updateRoot) title:"Erreur menu Iconia"
                )
            )
        )
    ) catch (
        -- En cas de coupure internet, on reste 100% silencieux. 
        -- L'utilisateur n'est pas derange a l'ouverture de 3ds Max.
    )
)
