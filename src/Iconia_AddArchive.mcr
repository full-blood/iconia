/*
================================================================================
Script Name: Iconia_AddToArchive
Category: Iconia
Description: Ajoute la sélection courante à un fichier .max archive existant.
================================================================================
*/
macroScript Iconia_AddToArchive
category:"Iconia"
buttonText:"Add to Archive"
tooltip:"Merge selection into an existing .max archive file"
(
    -- =============================================
    -- HELPERS
    -- =============================================

    fn getTimestamp = (
        local d = getLocalTime()
        local yyyy = d[1] as string
        local mm   = if d[2] < 10 then ("0" + d[2] as string) else (d[2] as string)
        local dd   = if d[4] < 10 then ("0" + d[4] as string) else (d[4] as string)
        local hh   = if d[5] < 10 then ("0" + d[5] as string) else (d[5] as string)
        local mn   = if d[6] < 10 then ("0" + d[6] as string) else (d[6] as string)
        return (yyyy + mm + dd + hh + mn)
    )

    fn findMaxExe = (
        local candidates = #(
            "C:\\Program Files\\Autodesk\\3ds Max 2026\\3dsmax.exe",
            "C:\\Program Files\\Autodesk\\3ds Max 2025\\3dsmax.exe",
            "C:\\Program Files\\Autodesk\\3ds Max 2024\\3dsmax.exe",
            "C:\\Program Files\\Autodesk\\3ds Max 2023\\3dsmax.exe",
            "C:\\Program Files\\Autodesk\\3ds Max 2022\\3dsmax.exe"
        )
        for p in candidates do (
            if doesFileExist p then return p
        )
        local currentExe = (getDir #maxroot) + "3dsmax.exe"
        if doesFileExist currentExe then return currentExe
        return undefined
    )

    fn wlog msg logFile = (
        local f = openFile logFile mode:"a"
        if f != undefined then (
            local d = getLocalTime()
            local ts = (d[5] as string) + ":" + (d[6] as string) + ":" + (d[7] as string)
            format ("[" + ts + "] " + msg + "\n") to:f
            close f
        )
    )

    fn readFile path = (
        local result = ""
        local f = openFile path mode:"r"
        if f != undefined then (
            while not eof f do result += (readLine f) + "\n"
            close f
        )
        return trimRight result
    )

    -- =============================================
    -- ENTRY POINT
    -- =============================================

    if selection.count == 0 then (
        messageBox "Nothing selected!" title:"Iconia Add to Archive"
        return false
    )

    local archiveTarget = getOpenFileName \
        caption:"Choisir l'archive .max cible" \
        types:"3ds Max (*.max)|*.max" \
        historyCategory:"ArchiveTarget"

    if archiveTarget == undefined then return false
    if not doesFileExist archiveTarget then (
        messageBox ("Fichier introuvable :\n" + archiveTarget) title:"Iconia Add to Archive"
        return false
    )

    local maxExe = findMaxExe()
    if maxExe == undefined then (
        messageBox "Impossible de trouver 3dsmax.exe." title:"Iconia Add to Archive"
        return false
    )

    local originalSelection = selection as array

    local tmpDir     = (getDir #temp) + "\\IconiaAddToArchive\\"
    local timestamp  = getTimestamp()
    local tmpMax     = tmpDir + timestamp + "_source.max"
    local tmpScript  = tmpDir + timestamp + "_worker.ms"
    local tmpDone    = tmpDir + timestamp + "_worker.done"
    local tmpError   = tmpDir + timestamp + "_worker.error"
    local tmpLog     = tmpDir + timestamp + "_worker.log"
    local previewJpg = (substituteString archiveTarget ".max" "") + ".jpg"

    HiddenDosCommand ("mkdir \"" + tmpDir + "\" 2>nul")

    -- --- 1. Save sélection ? temp.max -------------------------------------
    wlog ("saveNodes start — " + (originalSelection.count as string) + " objet(s)") tmpLog
    saveNodes originalSelection tmpMax

    if not doesFileExist tmpMax then (
        messageBox ("Echec saveNodes.\nChemin : " + tmpMax) title:"Iconia Add to Archive"
        return false
    )
    wlog "saveNodes OK" tmpLog

    -- --- 2. Ecrire le script worker ----------------------------------------
    local archiveEsc  = substituteString archiveTarget "\\" "\\\\"
    local tmpMaxEsc   = substituteString tmpMax        "\\" "\\\\"
    local previewEsc  = substituteString previewJpg    "\\" "\\\\"
    local tmpDoneEsc  = substituteString tmpDone       "\\" "\\\\"
    local tmpErrorEsc = substituteString tmpError      "\\" "\\\\"
    local tmpLogEsc   = substituteString tmpLog        "\\" "\\\\"

    -- Dossier startup UTILISATEUR (pas Program Files qui est protege en ecriture)
    -- getDir #userScripts => ...\AppData\Local\Autodesk\3dsMax\2026 - 64bit\ENU\scripts
    local userStartup  = (getDir #userScripts) + "\\Startup\\"
    HiddenDosCommand ("mkdir \"" + userStartup + "\" 2>nul")
    local startupCopy    = userStartup + timestamp + "_worker.ms"
    local startupCopyEsc = substituteString startupCopy "\\" "\\\\"

    local workerScript =
"fn wlog msg = (\n" +
"    local f = openFile \"" + tmpLogEsc + "\" mode:\"a\"\n" +
"    if f != undefined then ( format (msg + \"\\n\") to:f; close f )\n" +
")\n" +
"fn writeFile path msg = (\n" +
"    local f = createFile path\n" +
"    if f != undefined then ( format msg to:f; close f )\n" +
")\n" +
"try (\n" +
"    wlog \"[worker] Demarrage\"\n" +
"    local loadOK = loadMaxFile \"" + archiveEsc + "\" quiet:true\n" +
"    wlog (\"[worker] loadMaxFile : \" + loadOK as string)\n" +
"    local mergeOK = mergeMAXFile \"" + tmpMaxEsc + "\" #select #mergeDups quiet:true\n" +
"    wlog (\"[worker] mergeMAXFile : \" + mergeOK as string)\n" +
"    max vpt persp user\n" +
"    viewport.SetRenderLevel #smoothhighlights\n" +
"    max tool zoomextents all\n" +
"    max select none\n" +
"    local bmp = gw.getViewportDib()\n" +
"    if bmp != undefined then (\n" +
"        bmp.filename = \"" + previewEsc + "\"\n" +
"        save bmp\n" +
"        close bmp\n" +
"        wlog \"[worker] preview OK\"\n" +
"    ) else (\n" +
"        wlog \"[worker] WARNING preview echouee\"\n" +
"    )\n" +
"    local saveOK = saveMaxFile \"" + archiveEsc + "\" quiet:true\n" +
"    wlog (\"[worker] saveMaxFile : \" + saveOK as string)\n" +
"    writeFile \"" + tmpDoneEsc + "\" \"done\"\n" +
"    wlog \"[worker] DONE\"\n" +
") catch (\n" +
"    local err = getCurrentException()\n" +
"    wlog (\"[worker] EXCEPTION : \" + err)\n" +
"    writeFile \"" + tmpErrorEsc + "\" err\n" +
"    writeFile \"" + tmpDoneEsc + "\" \"error\"\n" +
")\n" +
"-- Auto-suppression du startup script\n" +
"deleteFile \"" + startupCopyEsc + "\"\n" +
"quitMax #noPrompt\n"

    local wf = createFile tmpScript
    if wf == undefined then (
        messageBox "Impossible de créer le script worker." title:"Iconia Add to Archive"
        return false
    )
    format workerScript to:wf
    close wf
    wlog ("Script worker ecrit : " + tmpScript) tmpLog

    -- --- 3. Lancer la 2ème instance ---------------------------------------
    wlog ("Lancement Max sans flags : " + maxExe) tmpLog
    -- Methode startup script : copier le worker dans scripts/startup puis lancer Max
    -- Max execute automatiquement tous les .ms dans ce dossier au demarrage
    -- C'est la methode la plus fiable, -U MAXScript pouvant etre ignore sur Max 2024+

    -- Copier le worker dans startup
    local srcF = openFile tmpScript mode:"r"
    local dstF = createFile startupCopy
    if srcF == undefined or dstF == undefined then (
        wlog "ERREUR : impossible de copier dans Startup" tmpLog
        messageBox ("Impossible d'ecrire dans :\n" + userStartup) title:"Iconia Add to Archive"
        return false
    )
    while not eof srcF do format (readLine srcF + "\n") to:dstF
    close srcF
    close dstF
    wlog ("Startup script copie : " + startupCopy) tmpLog

    -- Lancer Max sans flags restrictifs
    local psi = dotNetObject "System.Diagnostics.ProcessStartInfo"
    psi.FileName        = maxExe
    psi.Arguments       = ""
    psi.UseShellExecute = true
    local proc = (dotNetClass "System.Diagnostics.Process").Start psi
    if proc == undefined then (
        wlog "ERREUR : Process.Start a retourne undefined" tmpLog
        deleteFile startupCopy
        messageBox "Impossible de lancer la 2eme instance de 3ds Max." title:"Iconia Add to Archive"
        return false
    )
    wlog ("Process demarre, PID : " + proc.Id as string) tmpLog
    -- Note : le worker se supprime lui-meme de startup apres execution (voir workerScript)

    -- --- 4. Attendre le .done — timeout adaptatif -------------------------
    -- Sondage rapide au debut, ralenti ensuite
    local intervals = #()
    for i = 1 to 15 do append intervals 2    -- 0-30s   : toutes les 2s
    for i = 1 to 12 do append intervals 5    -- 30-90s  : toutes les 5s
    for i = 1 to  6 do append intervals 10   -- 90-150s : toutes les 10s

    local totalWaited = 0
    local finished    = false

    progressStart "Fusion en cours... (Echap pour annuler)"
    progressUpdate 0

    for interval in intervals while not finished do (
        sleep (interval as float)
        totalWaited += interval
        if doesFileExist tmpDone then (
            finished = true
        ) else (
            progressUpdate (amin #((totalWaited * 100 / 90), 95))
            if getProgressCancel() then exit
        )
    )

    progressEnd()

    -- --- 5. Résultat + debug ----------------------------------------------
    local logContent = readFile tmpLog

    if not finished then (
        messageBox (
            "Timeout apres " + totalWaited as string + "s\n\n" +
            "=== LOG ===\n" + logContent + "\n\n" +
            "Fichiers temp :\n" + tmpDir
        ) title:"Iconia Add to Archive — TIMEOUT"

    ) else if doesFileExist tmpError then (
        local errContent = readFile tmpError
        messageBox (
            "Erreur worker :\n" + errContent + "\n\n" +
            "=== LOG ===\n" + logContent
        ) title:"Iconia Add to Archive — ERREUR"
        deleteFile tmpError

    ) else (
        local objNames = ""
        local limit = amin #(originalSelection.count, 5)
        for i = 1 to limit do
            objNames += "  - " + originalSelection[i].name + "\n"
        if originalSelection.count > 5 then
            objNames += "  ... (" + (originalSelection.count as string) + " objets total)\n"

        messageBox (
            "OK en " + totalWaited as string + "s\n\n" +
            "Archive : " + archiveTarget + "\n" +
            "Preview : " + previewJpg + "\n\n" +
            "Objets ajoutes :\n" + objNames
        ) title:"Iconia Add to Archive — OK"
    )

    -- Nettoyage (tmpLog garde pour debug eventuel)
    deleteFile tmpMax
    deleteFile tmpScript
    if doesFileExist tmpDone then deleteFile tmpDone
)
