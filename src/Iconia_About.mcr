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
    -- Source des mises a jour : partage LAN (UNC pour ne pas dependre de L:)
    local updateRoot        = "\\\\CgLibrary\\CgLibrary\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\Iconia\\"
    local remoteVersionFile = updateRoot + "version.txt"
    local remoteMZPFile     = updateRoot + "Iconia.mzp"

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
        if doesFileExist remoteVersionFile then (
            local remoteFile = openFile remoteVersionFile mode:"r"
            remoteVer = trimRight (readLine remoteFile)
            close remoteFile
            fetchOK = true
        )
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
            local tempDir  = getDir #temp
            local mzpPath  = tempDir + "\\Iconia_update.mzp"

            -- Télécharge le .mzp depuis GitHub Releases (asset direct)
            if doesFileExist mzpPath do deleteFile mzpPath
            copyFile remoteMZPFile mzpPath

            if doesFileExist mzpPath then (
                -- fileIn lance l'installation de façon plus fiable que installPkg
                fileIn mzpPath
                messageBox ("Iconia mis à jour vers v" + remoteVer + ".\nSi le menu n'est pas à jour, relancez 3ds Max pour appliquer.") title:"Iconia Update"
            ) else (
                messageBox ("Copie depuis le partage LAN echouee.\nVerifiez l'acces a :\n" + updateRoot) title:"Erreur"
            )
        ) catch (
            messageBox ("Erreur lors de la copie LAN :\n" + (getCurrentException()) + "\n\nPartage :\n" + updateRoot) title:"Erreur"
        )
    )
)
