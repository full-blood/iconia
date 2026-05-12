/*
================================================================================
Script Name: Iconia_About
Category: Iconia
Description: Affiche la version et contrôle les mises à jour.
================================================================================
*/
macroScript Iconia_About category:"Iconia" tooltip:"About"
(
    -- -----------------------------------------------
    -- Config
    -- -----------------------------------------------
    local githubUser    = "full-blood"
    local githubRepo    = "iconia"
    local branch        = "main"
    local baseRawURL    = "https://raw.githubusercontent.com/" + githubUser + "/" + githubRepo + "/" + branch + "/"
    local releasesURL   = "https://github.com/" + githubUser + "/" + githubRepo + "/releases/latest"

    -- -----------------------------------------------
    -- Version locale
    -- -----------------------------------------------
    local root        = (getDir #userScripts) + "\\Iconia"
    local versionFile = root + "\\version.txt"
    local localVer    = "0.0.0"

    if doesFileExist versionFile then (
        local f = openFile versionFile mode:"r"
        localVer = trimRight (readLine f)
        close f
    )

    -- -----------------------------------------------
    -- NOUVEAU : Comparaison Mathématique Réelle (SemVer)
    -- -----------------------------------------------
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

    -- -----------------------------------------------
    -- Version distante via GitHub raw (Avec Anti-Cache)
    -- -----------------------------------------------
    local remoteVer   = ""
    local fetchOK     = false

    try (
        -- Forcer TLS 1.2 pour l'API GitHub
        local securityProtocolType = dotNetClass "System.Net.SecurityProtocolType"
        local servicePointManager = dotNetClass "System.Net.ServicePointManager"
        servicePointManager.SecurityProtocol = securityProtocolType.Tls12

        local http = dotNetObject "System.Net.WebClient"
        http.Headers.Add "User-Agent" "MaxScript"
        
        -- Anti-Cache
        local cacheBuster = (random 1 9999999) as string
        remoteVer = trimRight (http.DownloadString (baseRawURL + "version.txt?t=" + cacheBuster))
        fetchOK   = true
    ) catch (
        remoteVer = ""
    )

    -- -----------------------------------------------
    -- Comparaison Intelligente
    -- -----------------------------------------------
    local updateAvail = fetchOK and (remoteVer != "") and (isNewerVersion remoteVer localVer)

    -- -----------------------------------------------
    -- UI
    -- -----------------------------------------------
    local msg = "Iconia v" + localVer + "\n\nGestionnaire de scripts automatisé.\n\n"

    if not fetchOK then
        msg += "⚠ Impossible de vérifier les mises à jour (pas de connexion ?)."
    else if updateAvail then
        msg += "🔔 Mise à jour disponible : v" + remoteVer + "\n(cliquez OK pour installer)"
    else
        msg += "✔ Vous avez la dernière version."

    -- Bouton OK / Annuler seulement si update dispo
    local doUpdate = false
    if updateAvail then (
        doUpdate = (queryBox msg title:"Iconia" beep:false)
    ) else (
        messageBox msg title:"Iconia"
    )

    -- -----------------------------------------------
    -- Auto-update : télécharge le .mzp et le run
    -- -----------------------------------------------
    if doUpdate then (
        try (
            -- /!\ LIGNES CRUCIALES POUR GITHUB : Forcer TLS 1.2 /!\
            local securityProtocolType = dotNetClass "System.Net.SecurityProtocolType"
            local servicePointManager = dotNetClass "System.Net.ServicePointManager"
            servicePointManager.SecurityProtocol = securityProtocolType.Tls12

            local http     = dotNetObject "System.Net.WebClient"
            http.Headers.Add "User-Agent" "MaxScript"
            local tempDir  = getDir #temp
            local mzpPath  = tempDir + "\\Iconia_update.mzp"

            -- Télécharge le .mzp depuis GitHub Releases (asset direct)
            local mzpURL = "https://github.com/" + githubUser + "/" + githubRepo + "/releases/latest/download/Iconia.mzp"
            http.DownloadFile mzpURL mzpPath

            if doesFileExist mzpPath then (
                -- fileIn lance l'installation de façon plus fiable que installPkg
                fileIn mzpPath
                messageBox ("Iconia mis à jour vers v" + remoteVer + ".\nRelancez 3ds Max pour appliquer.") title:"Iconia Update"
            ) else (
                messageBox "Téléchargement échoué. Essayez manuellement :\n" + releasesURL title:"Erreur"
            )
        ) catch (
            messageBox ("Erreur lors du téléchargement :\n" + (getCurrentException()) + "\n\nLien manuel :\n" + releasesURL) title:"Erreur"
        )
    )
)