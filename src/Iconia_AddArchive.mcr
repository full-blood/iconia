/*
================================================================================
Script Name: Iconia_AddToArchive
Category: Iconia
Description: Ajoute la sélection courante à un fichier .max archive existant.
================================================================================
*/
macroScript Iconia_AddToArchive
category:"Iconia"
buttonText:"Add to existing Archive"
tooltip:"Merge selection into an existing .max archive file"
(
    -- =============================================
    -- VARIABLES SCRIPT-LEVEL (Accessibles par les rollouts)
    -- =============================================
    global _iconiaChosenArchive
    global _iconiaSuccessImg
    global _iconiaSuccessMsg
    
    local archivePath = undefined
    local jpgFiles = #()
    local ArchiveBrowserAdd
    local IconiaSuccessRollout

    -- =============================================
    -- HELPERS (niveau global du macroScript)
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
        currentyear = (getLocalTime())[1]
        currentyear += 2
        for i = 1 to 10 do (
            p = "C:\\Program Files\\Autodesk\\3ds Max "+(currentyear as string)+"\\3dsmax.exe"
            if doesFileExist p then return p
            currentyear -= 1
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

    -- Fonction pour afficher le message de succès avec l'image
    fn showSuccessUI imgPath maxName = (
        _iconiaSuccessImg = imgPath
        _iconiaSuccessMsg = "sélection enregistrée dans " + maxName

        try(destroyDialog IconiaSuccessRollout)catch()
        
        rollout IconiaSuccessRollout "Iconia - Terminé" width:800 height:500 (
            dotNetControl pb "System.Windows.Forms.PictureBox" width:780 height:420 pos:[10,10]
            label lblMsg "" pos:[10, 440] width:780 height:20
            button btnOk "OK" width:120 height:30 pos:[340, 465]

            on IconiaSuccessRollout open do (
                lblMsg.text = _iconiaSuccessMsg
                -- (La ligne lblMsg.alignment qui faisait planter a été retirée ici)
                
                -- Chargement sécurisé de l'image
                if doesFileExist _iconiaSuccessImg then (
                    try (
                        local fs = (dotNetClass "System.IO.File").OpenRead _iconiaSuccessImg
                        local imgClass = dotNetClass "System.Drawing.Image"
                        pb.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom
                        pb.Image = imgClass.FromStream fs
                        fs.Close()
                    ) catch (
                        lblMsg.text = _iconiaSuccessMsg + " (Aperçu indisponible)"
                    )
                )
            )

            on btnOk pressed do destroyDialog IconiaSuccessRollout
        )
        createDialog IconiaSuccessRollout modal:true
    )

    -- =============================================
    -- FONCTION PRINCIPALE
    -- =============================================

    fn main = (

        -- Garde-fou : sélection obligatoire
        if selection.count == 0 then (
            messageBox "Nothing selected!" title:"Iconia Add to Archive"
            return false
        )

        local originalSelection = selection as array

        -- =============================================
        -- BROWSER VISUEL — choix de l'archive cible
        -- =============================================

        -- Réinitialisation des variables partagées à chaque exécution de main()
        _iconiaChosenArchive = undefined
        archivePath = undefined
        jpgFiles = #()

        -- Trouver le dossier archive du projet courant
        local dir_array = (GetDirectories (maxFilePath + "/*"))
        for d in dir_array do (
            local pathParts = filterString d "\\"
            local lastFolder = pathParts[pathParts.count]
            if matchPattern lastFolder pattern:"*archive*" then
                archivePath = (maxFilePath + lastFolder + "\\")
        )

        -- Collecter les JPG (tableau vide si dossier introuvable)
        if archivePath != undefined then (
            jpgFiles = (getFiles (archivePath + "*.jpg"))
            join jpgFiles (getFiles (archivePath + "*.jpeg"))
        )

        try (destroyDialog ArchiveBrowserAdd) catch ()

        rollout ArchiveBrowserAdd "Choisir l'archive cible" width:960 height:1080
        (
            dotNetControl flp "System.Windows.Forms.FlowLayoutPanel" width:940 height:970 pos:[10,10]
            button btnOtherFolder "Autre dossier..." width:160 height:34 pos:[10,990]
            button btnCancel      "Annuler"          width:120 height:34 pos:[820,990]

            fn onThumbnailClicked s e = (
                local imgPath = s.Tag
                local maxFile = (getFilenamePath imgPath) + (getFilenameFile imgPath) + ".max"
                if doesFileExist maxFile then (
                    if queryBox ("Ajouter la sélection dans :\n\n" + (getFilenameFile maxFile)) \
                        title:"Confirmation" do (
                        _iconiaChosenArchive = maxFile
                        destroyDialog ArchiveBrowserAdd
                    )
                ) else (
                    messageBox ("Aucun fichier .max correspondant :\n" + maxFile) \
                        title:"Iconia Add to Archive — Erreur"
                )
            )

            fn loadImages fileList = (
                flp.Controls.Clear()
                local imgClass = dotNetClass "System.Drawing.Image"
                for i = fileList.count to 1 by -1 do (
                    local f  = fileList[i]
                    
                    try (
                        local fs = (dotNetClass "System.IO.File").OpenRead f
                        local loadedImg = imgClass.FromStream fs
                        fs.Close()

                        local pb = dotNetObject "System.Windows.Forms.PictureBox"
                        pb.Width    = 1300
                        pb.Height   = 650
                        pb.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom
                        pb.Image    = loadedImg
                        pb.Tag      = f
                        pb.Cursor   = (dotNetClass "System.Windows.Forms.Cursors").Hand
                        pb.Margin   = dotNetObject "System.Windows.Forms.Padding" 5

                        local tt = dotNetObject "System.Windows.Forms.ToolTip"
                        tt.SetToolTip pb ((getFilenameFile f) + ".max")

                        dotNet.addEventHandler pb "Click" onThumbnailClicked
                        flp.Controls.Add pb
                    ) catch (
                        format "?? Iconia - Impossible de charger l'image (Format invalide ?) : %\n" f
                    )
                )
            )

            on ArchiveBrowserAdd open do (
                flp.AutoScroll   = true
                flp.WrapContents = true
                flp.BackColor    = (dotNetClass "System.Drawing.Color").FromArgb 40 40 40

                if jpgFiles.count > 0 then (
                    loadImages jpgFiles
                ) else (
                    local lbl = dotNetObject "System.Windows.Forms.Label"
                    lbl.Text = if archivePath == undefined \
                        then "Dossier 'archive' introuvable.\nUtilisez 'Autre dossier...' pour naviguer." \
                        else "Aucune image JPG trouvée.\nUtilisez 'Autre dossier...' pour naviguer."
                    lbl.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 200 200 200
                    lbl.Width  = 900
                    lbl.Height = 60
                    lbl.Margin = dotNetObject "System.Windows.Forms.Padding" 10
                    flp.Controls.Add lbl
                )
            )

            on btnOtherFolder pressed do (
                local picked = getOpenFileName \
                    caption:"Choisir l'archive .max cible" \
                    types:"3ds Max (*.max)|*.max" \
                    historyCategory:"ArchiveTarget"
                if picked != undefined then (
                    if doesFileExist picked then (
                        _iconiaChosenArchive = picked
                        destroyDialog ArchiveBrowserAdd
                    ) else (
                        messageBox ("Fichier introuvable :\n" + picked) \
                            title:"Iconia Add to Archive"
                    )
                )
            )

            on btnCancel pressed do destroyDialog ArchiveBrowserAdd
        )

        createDialog ArchiveBrowserAdd modal:true

        if _iconiaChosenArchive == undefined then return false

        local archiveTarget = _iconiaChosenArchive

        -- =============================================
        -- PIPELINE : sauvegarde sélection + worker Max
        -- =============================================

        local maxExe = findMaxExe()
        if maxExe == undefined then (
            messageBox "Impossible de trouver 3dsmax.exe." title:"Iconia Add to Archive"
            return false
        )

        local tmpDir     = (getDir #temp) + "\\IconiaAddToArchive\\"
        local vtimestamp = getTimestamp()
        local tmpMax     = tmpDir + vtimestamp + "_source.max"
        local tmpScript  = tmpDir + vtimestamp + "_worker.ms"
        local tmpDone    = tmpDir + vtimestamp + "_worker.done"
        local tmpError   = tmpDir + vtimestamp + "_worker.error"
        local tmpLog     = tmpDir + vtimestamp + "_worker.log"
        local previewJpg = (substituteString archiveTarget ".max" "") + ".jpg"

        HiddenDosCommand ("mkdir \"" + tmpDir + "\" 2>nul")

        -- 1. saveNodes ? temp.max
        wlog ("saveNodes start — " + (originalSelection.count as string) + " objet(s)") tmpLog
        saveNodes originalSelection tmpMax

        if not doesFileExist tmpMax then (
            messageBox ("Echec saveNodes.\nChemin : " + tmpMax) title:"Iconia Add to Archive"
            return false
        )
        wlog "saveNodes OK" tmpLog

        -- 2. Écrire le script worker
        local archiveEsc  = substituteString archiveTarget "\\" "\\\\"
        local tmpMaxEsc   = substituteString tmpMax        "\\" "\\\\"
        local previewEsc  = substituteString previewJpg    "\\" "\\\\"
        local tmpDoneEsc  = substituteString tmpDone       "\\" "\\\\"
        local tmpErrorEsc = substituteString tmpError      "\\" "\\\\"
        local tmpLogEsc   = substituteString tmpLog        "\\" "\\\\"

        local userStartup    = (getDir #userScripts) + "\\Startup\\"
        HiddenDosCommand ("mkdir \"" + userStartup + "\" 2>nul")
        local startupCopy    = userStartup + vtimestamp + "_worker.ms"
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
        "deleteFile \"" + startupCopyEsc + "\"\n" +
        "wlog \"[worker] startup script supprime\"\n" +
        "global _iconiaQuitTimer\n" +
        "_iconiaQuitTimer = dotNetObject \"System.Windows.Forms.Timer\"\n" +
        "_iconiaQuitTimer.Interval = 2000\n" +
        "fn onQuitTimer s e = (\n" +
        "    _iconiaQuitTimer.Stop()\n" +
        "    quitMax #noPrompt\n" +
        ")\n" +
        "dotNet.addEventHandler _iconiaQuitTimer \"Tick\" onQuitTimer\n" +
        "try (\n" +
        "    wlog \"[worker] Demarrage\"\n" +
        "    local loadOK = loadMaxFile \"" + archiveEsc + "\" quiet:true\n" +
        "    wlog (\"[worker] loadMaxFile : \" + loadOK as string)\n" +
        "    local mergeOK = mergeMAXFile \"" + tmpMaxEsc + "\" #select #mergeDups quiet:true\n" +
        "    wlog (\"[worker] mergeMAXFile : \" + mergeOK as string)\n" +
        "    clearSelection()\n" + 
        "    max vpt persp user\n" +
        "    viewport.SetRenderLevel #smoothhighlights\n" +
        "    max tool zoomextents all\n" +
        "    completeRedraw()\n" + 
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
        "    wlog \"[worker] DONE — timer de fermeture arme\"\n" +
        ") catch (\n" +
        "    local err = getCurrentException()\n" +
        "    wlog (\"[worker] EXCEPTION : \" + err)\n" +
        "    writeFile \"" + tmpErrorEsc + "\" err\n" +
        "    writeFile \"" + tmpDoneEsc + "\" \"error\"\n" +
        "    wlog \"[worker] ERROR — timer de fermeture arme\"\n" +
        ")\n" +
        "_iconiaQuitTimer.Start()\n"

        local wf = createFile tmpScript
        if wf == undefined then (
            messageBox "Impossible de créer le script worker." title:"Iconia Add to Archive"
            return false
        )
        format workerScript to:wf
        close wf
        wlog ("Script worker ecrit : " + tmpScript) tmpLog

        -- 3. Copier dans Startup et lancer Max
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

        local psi = dotNetObject "System.Diagnostics.ProcessStartInfo"
        psi.FileName        = maxExe
        psi.Arguments       = ""  -- <-- Démarrage normal
        psi.UseShellExecute = true
        local proc = (dotNetClass "System.Diagnostics.Process").Start psi
        if proc == undefined then (
            wlog "ERREUR : Process.Start a retourne undefined" tmpLog
            deleteFile startupCopy
            messageBox "Impossible de lancer la 2eme instance de 3ds Max." title:"Iconia Add to Archive"
            return false
        )
        wlog ("Process demarre, PID : " + proc.Id as string) tmpLog

        -- 4. Polling .done — timeout adaptatif
        local intervals = #()
        for i = 1 to 15 do append intervals 2
        for i = 1 to 12 do append intervals 5
        for i = 1 to  6 do append intervals 10

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

        -- 5. Résultat
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
            -- Affichage de la nouvelle fenêtre visuelle de succès
            showSuccessUI previewJpg ((getFilenameFile archiveTarget) + ".max")
        )

        -- Nettoyage
        deleteFile tmpMax
        deleteFile tmpScript
        if doesFileExist tmpDone then deleteFile tmpDone

        return true
    )

    -- Appel de la fonction principale
    main()
)