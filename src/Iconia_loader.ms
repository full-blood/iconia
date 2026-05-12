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
        print "MaxStack menu loaded..."
    ) catch (
        format "MaxStack Loader Error (Menu) : %\n" (getCurrentException())
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

    -- Config GitHub
    local githubUser    = "full-blood"
    local githubRepo    = "maxstack"
    local branch        = "main"
    local baseRawURL    = "https://raw.githubusercontent.com/" + githubUser + "/" + githubRepo + "/" + branch + "/"
    local releasesURL   = "https://github.com/" + githubUser + "/" + githubRepo + "/releases/latest"

    -- Version locale
    local root        = (getDir #userScripts) + "\\MaxStack"
    local versionFile = root + "\\version.txt"
    local localVer    = "0.0.0"

    if doesFileExist versionFile then (
        local f = openFile versionFile mode:"r"
        localVer = trimRight (readLine f)
        close f
    )

    -- Check en arriere-plan
    try (
        local securityProtocolType = dotNetClass "System.Net.SecurityProtocolType"
        local servicePointManager = dotNetClass "System.Net.ServicePointManager"
        servicePointManager.SecurityProtocol = securityProtocolType.Tls12

        local http = dotNetObject "System.Net.WebClient"
        http.Headers.Add "User-Agent" "MaxScript"
        
        local cacheBuster = (random 1 9999999) as string
        local remoteVer = trimRight (http.DownloadString (baseRawURL + "version.txt?t=" + cacheBuster))

        -- Si on trouve une mise a jour, on propose a l'utilisateur
        if (remoteVer != "") and (isNewerVersion remoteVer localVer) then (
            local msg = "Une nouvelle version de MaxStack (v" + remoteVer + ") est disponible !\n(Version actuelle : " + localVer + ")\n\nVoulez-vous la telecharger et l'installer maintenant ?"
            
            -- queryBox pose la question. Si l'utilisateur clique "Oui", ca lance l'update.
            if (queryBox msg title:"Mise a jour MaxStack" beep:true) then (
                print "Telechargement de la mise a jour MaxStack..."
                
                local tempDir  = getDir #temp
                local mzpPath  = tempDir + "\\MaxStack_update.mzp"
                local mzpURL = "https://github.com/" + githubUser + "/" + githubRepo + "/releases/latest/download/MaxStack.mzp"
                
                http.DownloadFile mzpURL mzpPath

                if doesFileExist mzpPath then (
                    fileIn mzpPath
                    -- Le message de succes du fileIn prendra le relais
                ) else (
                    messageBox "Echec du telechargement.\nVous pouvez mettre a jour manuellement via le menu 'A propos'." title:"Erreur MaxStack"
                )
            )
        )
    ) catch (
        -- En cas de coupure internet, on reste 100% silencieux. 
        -- L'utilisateur n'est pas derange a l'ouverture de 3ds Max.
    )
)