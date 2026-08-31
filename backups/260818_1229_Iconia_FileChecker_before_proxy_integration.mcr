/*
================================================================================
Script Name: Iconia_FileChecker
Category: Iconia
Description: Outil de vérification global avant d'intégrer un asset dans la bibliothèque 3D.
             Intègre les étapes : Corona & Clean Reset, Filename, Maps, Pivots, 
             Wirecolor, Layers, Names, Preview, et Keywords.
================================================================================
*/

macroScript Iconia_FileChecker
    category:"Iconia" 
    tooltip:"File Checker"
    buttonText:"File Checker"
(
    local rlMasterChecker
    local rl_selectImage
    local rl_Splash

    try(DestroyDialog rlMasterChecker) catch()
    try(DestroyDialog rl_selectImage) catch()

    -- ===========================================================
    -- VARIABLES GLOBALES ET CACHE (Partagées entre Splash et Main)
    -- ===========================================================
    struct CategoryDataStruct ( catName, subcats = #() )
    local database = #()
    local keyword_library = #()
    local netKeywords_Cache = undefined
    local step9_Initialized = false
	local folderAliases = #()

    fn toNetArray arr = (
        local na = dotNetObject "System.String[]" arr.count
        for i = 1 to arr.count do na.SetValue arr[i] (i-1)
        na
    )

    fn fillComboBox ctrl arr = (
        ctrl.BeginUpdate()
        ctrl.Items.Clear()
        if arr.count > 0 do ctrl.Items.AddRange (toNetArray arr)
        ctrl.EndUpdate()
    )
	
	fn resolveFolderAlias rawName = (
		for pair in folderAliases do (
			if (stricmp pair[1] rawName == 0) do return pair[2]
		)
		return rawName  -- pas d'alias trouvé, on retourne tel quel
	)

    -- ===========================================================
    -- FENÊTRE DE CHARGEMENT (SPLASH SCREEN)
    -- ===========================================================
    fn rl_Splash =
    (
        -- LOAD DB CSV
        local csvPath = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_Categories_List.csv"
        database = #()
        if doesFileExist csvPath do (
            local f = openFile csvPath
            while not eof f do (
                local parts = filterString (readLine f) ";"
                if parts.count >= 2 do (
                    local cName    = trimLeft (trimRight parts[1])
                    local sName    = trimLeft (trimRight parts[2])
                    local foundCat = undefined
                    for d in database do ( if d.catName == cName do foundCat = d )
                    if foundCat == undefined do ( foundCat = CategoryDataStruct catName:cName; append database foundCat )
                    appendIfUnique foundCat.subcats sName
                )
            )
            close f
        )

        -- LOAD KEYWORDS LIBRARY + PRÉ-CALCUL .NET
        local txtPathLib = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_Keywords_List.txt"
        keyword_library = #()
        if doesFileExist txtPathLib do (
            local fLib = openFile txtPathLib
            while not eof fLib do (
                local l = trimLeft (trimRight (readLine fLib))
                if l != "" do appendIfUnique keyword_library l
            )
            close fLib
            sort keyword_library
            
            -- Précalcul .NET pendant le chargement
            netKeywords_Cache = toNetArray keyword_library 
        )

        -- Ferme le Splash et ouvre la fenêtre principale
        try(DestroyDialog rlMasterChecker) catch()
        CreateDialog rlMasterChecker style:#(#style_titlebar, #style_sysmenu)
    )

    -- ===========================================================
    -- ROLLOUT SECONDAIRE : SÉLECTION D'IMAGE
    -- ===========================================================
    rollout rl_selectImage "Select preview image" width:620 height:560 (
        local imageFiles = #()
        local imgfolder = ""
        local imgbaseName = ""

        listbox lb_images "" pos:[10,10] width:600 height:15
        dotNetControl pb_preview "System.Windows.Forms.PictureBox" pos:[10,260] width:600 height:240
        button bt_ok "Use selected image" width:200 align:#center offset:[0,5]

        on rl_selectImage open do ( 
            pb_preview.SizeMode = (dotNetClass "System.Windows.Forms.PictureBoxSizeMode").Zoom
            pb_preview.BorderStyle = (dotNetClass "System.Windows.Forms.BorderStyle").FixedSingle
            pb_preview.BackColor = (dotNetClass "System.Drawing.Color").FromARGB 50 50 50 
            
            imgfolder = maxFilePath
            imgbaseName = getFilenameFile maxFileName
            imageFiles = #()
            
            for ext in #(".jpg", ".jpeg", ".png", ".bmp") do (
                join imageFiles (getFiles (imgfolder + "*" + ext))
            )
            
            lb_images.items = for f in imageFiles collect (filenameFromPath f)
        )
        
        on lb_images selected idx do ( 
            try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch()
            try(pb_preview.Image = (dotNetObject "System.Drawing.Bitmap" imageFiles[idx]))catch() 
        )
        
        on bt_ok pressed do (
            if lb_images.selection != 0 then (
                local sourceFile = imageFiles[lb_images.selection]
                local ext = getFilenameType sourceFile
                local destFile = imgfolder + imgbaseName + ext
                
                try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch()
                
                if copyFile sourceFile destFile then ( 
                    destroyDialog rl_selectImage
                    try(rlMasterChecker.checkPreviewImage())catch() 
                ) else (
                    messageBox "Erreur lors de la copie du fichier." title:"Preview image"
                )
            ) else (
                messageBox "Sélectionne une image." title:"Preview image"
            )
        )
        
        on rl_selectImage close do ( 
            try(if pb_preview.Image != undefined do pb_preview.Image.Dispose())catch() 
        )
    )

    -- ===========================================================
    -- ROLLOUT PRINCIPAL : MASTER CHECKER
    -- ===========================================================
    rollout rlMasterChecker "MaxStack — Master Checker" width:800 height:600
    (
        local updateChecklistUI, hideAllUI, showCurrentStepUI, switchStep
        local doCheckCorona, completeStep1, doCleanReset, checkSceneMaterials, collectMaterials
        local getSystemUnitCentimeters, normalizeSceneUnitsToCentimeters
        local isPluginCleanupCandidate, collectMissingPluginItems, promptMissingPlugins, runPruneOptions, validateCleanScene
        local removeCamerasForAsset, removeXRefsForAsset, removeEmptyOrMissingObjects, removeParticleViewObjects
        local removeAnimationKeysForAsset, removeAnimationLayersForAsset, removeMissingCoronaAssets, removeRootCustomAttributes, removeJunkEffects
        local doCheckFilename, cleanMaxFileName, doRenameOnDisk, completeStep2
        local collectAllBitmaps, checkBitmapStatus, relinkBitmaps, findMapInProject, moveProjectMapsToCanonicalFolder, getLocalMapsFolder, getUniqueLocalFile, copyOutsideMapsToLocal, doStep3_Scan, doStep3_Relink, completeStep3
        local rPivot, rGrpPivot, hasDiffScale
        local wColor, listAllLayers
        local getPrefix, updateNameList, renameItemFromList
        local checkPreviewImage
        local initDotNetCombobox, getAiKeywords, initStep9Keywords

        -- ===========================================================
        -- COLONNE GAUCHE : CHECKLIST
        -- ===========================================================
        label lbl_step1 "[ . ] Check Corona & Reset" pos:[15, 20]  width:145 height:16
        label lbl_step2 "[   ] Check filename"       pos:[15, 45]  width:145 height:16
        label lbl_step3 "[   ] Check maps"           pos:[15, 70]  width:145 height:16
        label lbl_step4 "[   ] Check pivots"         pos:[15, 95]  width:145 height:16
        label lbl_step5 "[   ] Check wirecolor"      pos:[15, 120] width:145 height:16
        label lbl_step6 "[   ] Check layers"         pos:[15, 145] width:145 height:16
        label lbl_step7 "[   ] Check names"          pos:[15, 170] width:145 height:16
        label lbl_step8 "[   ] Check preview"        pos:[15, 195] width:145 height:16
        label lbl_step9 "[   ] Check keywords"       pos:[15, 220] width:145 height:16

        button btn_prev "<< Prev" pos:[15, 560] width:65 height:25 enabled:false
        button btn_next "Next >>" pos:[85, 560] width:65 height:25
        label lbl_sep "" pos:[160, 15] width:1 height:565 style_sunkenedge:true

        -- ===========================================================
        -- UI ÉTAPE 1 : CORONA & CLEAN RESET
        -- ===========================================================
        label lbl_reload "⏳ Chargement en cours..." pos:[400,300] visible:true
        listBox lst_log_s1 "" pos:[180,20] width:590 height:12 visible:false
        groupBox grp_prune_s1 "PRUNE / CLEAN OPTIONS" pos:[180,225] width:590 height:205 visible:false
        checkbox chk_removeCameras_s1 "Remove cameras" pos:[195,250] width:165 checked:true visible:false
        checkbox chk_removeXRefs_s1 "Remove XRefs" pos:[195,275] width:165 checked:true visible:false
        checkbox chk_garbage_s1 "Garbage collector" pos:[195,300] width:165 checked:true visible:false
        checkbox chk_memory_s1 "Clear Undo + bitmap cache" pos:[195,325] width:165 checked:true visible:false
        checkbox chk_reactor_s1 "Reactor Collision (legacy)" pos:[195,350] width:165 checked:true visible:false
        checkbox chk_animLayers_s1 "Remove animation layers" pos:[195,375] width:165 checked:true visible:false
        checkbox chk_missingObjects_s1 "Remove missing / empty objects" pos:[195,400] width:180 checked:true visible:false
        checkbox chk_animKeys_s1 "Remove all animation keys" pos:[410,250] width:165 checked:true visible:false
        checkbox chk_particleView_s1 "Remove invalid Particle View" pos:[410,275] width:165 checked:true visible:false
        checkbox chk_coronaAssets_s1 "Remove missing Corona assets" pos:[410,300] width:180 checked:true visible:false
        checkbox chk_rootCA_s1 "Remove known Root CAs" pos:[410,325] width:165 checked:true visible:false
        checkbox chk_missingPlugins_s1 "Check missing plugins" pos:[410,350] width:165 checked:true visible:false
        checkbox chk_junkEffects_s1 "Remove junk effects" pos:[410,375] width:165 checked:true visible:false
        button btn_main_s1 "CHECK CORONA\n& CLEAN RESET" pos:[405,455] width:140 height:60 align:#center visible:false
        button btn_converter_s1 "OPEN CORONA\nCONVERTER" pos:[265,445] width:140 height:60 visible:false
        button btn_done_s1 "CORONA\nOK ✔" pos:[485,445] width:140 height:60 visible:false
        button btn_recheck_s1 "RECHECK" pos:[375,510] width:140 height:40 align:#center visible:false

        -- ===========================================================
        -- UI ÉTAPE 2 : FILE CHECKER
        -- ===========================================================
        listBox lst_log_s2 "" pos:[180,20] width:590 height:12 visible:false
        label lbl_prev_title_s2 "Preview :" pos:[180,208] width:590 height:16 visible:false
        edittext edt_before_s2 "" pos:[180,228] width:590 height:22 readOnly:true visible:false
        label lbl_arrow_s2 "▼" pos:[465,254] width:30 height:18 align:#center visible:false
        edittext edt_after_s2  "" pos:[180,274] width:590 height:22 visible:false
        button btn_main_s2 "RETRY CHECK" pos:[635,525] width:120 height:60 align:#center visible:false
        button btn_confirm_s2 "RENAME FILE\nON DISK" pos:[405,400] width:120 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 3 : MAPS CHECKER
        -- ===========================================================
        listBox lst_log_s3 "" pos:[180,20] width:590 height:16 visible:false
        checkbox chk_fixOutside_s3 "Relink 'Outside' maps to local folder if found" pos:[180,270] checked:true visible:false
        
        button btn_force_s3 "Open Asset Tracking" pos:[190,515] width:120 height:60 enabled:false visible:false
        button btn_copy_local_s3 "COPY MAPS\nTO LOCAL" pos:[343,515] width:120 height:60 enabled:false visible:false
        button btn_recheck_s3 "RECHECK" pos:[343,515] width:120 height:60 visible:false
        button btn_remove_missing_s3 "REMOVE MISSING" pos:[496,515] width:120 height:60 visible:false
        button btn_main_s3 "CHECK MAPS" pos:[496,515] width:120 height:60 align:#center visible:false
        button btn_done_s3 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 4 : PIVOTS
        -- ===========================================================
        listBox lst_log_s4 "" pos:[180,20] width:590 height:12 visible:false
        button btn_piv_each_s4 "RESET EACH PIVOT" pos:[310,515] width:140 height:60 visible:false
        button btn_piv_grp_s4 "RESET GROUPED PIVOT" pos:[470,515] width:140 height:60 visible:false
        button btn_done_s4 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 5 : WIRECOLOR
        -- ===========================================================
        listBox lst_log_s5 "" pos:[180,20] width:590 height:12 visible:false
        button btn_wire_s5 "UNDO WIRECOLOR" pos:[470,515] width:140 height:60 visible:false
        button btn_done_s5 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 6 : LAYERS (Bouton Combiné)
        -- ===========================================================
        listBox lst_log_s6 "Layers in scene:" pos:[180,20] width:590 height:16 visible:false
        button btn_lay_fix_s6 "MOVE ALL TO LAYER 0\n& REMOVE UNUSED" pos:[375,350] width:200 height:80 visible:false
        button btn_done_s6 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 7 : NAMES
        -- ===========================================================
		multiListBox lst_names_s7 "Object Names:" pos:[180, 20] width:590 height:26 visible:false
		
        label lbl_n_pref "Prefix:" pos:[510,405] width:60 height:16 visible:false
        edittext edt_n_pref "" pos:[570,403] width:200 height:20 visible:false
        label lbl_n_base "Base Name:" pos:[510,430] width:60 height:16 visible:false
        edittext edt_n_base "" pos:[570,428] width:200 height:20 visible:false
        
        button btn_n_all "Name All" pos:[510,460] width:80 height:30 visible:false
        button btn_n_grp "Name Group" pos:[595,460] width:85 height:30 visible:false
        button btn_n_sel "Name Selected" pos:[685,460] width:85 height:30 visible:false
        
        label lbl_n_search "Search:" pos:[180,405] width:60 height:16 visible:false
        edittext edt_n_search "" pos:[240,403] width:200 height:20 visible:false
        label lbl_n_repl "Replace:" pos:[180,430] width:60 height:16 visible:false
        edittext edt_n_repl "" pos:[240,428] width:200 height:20 visible:false
        button btn_n_replace "Search & Replace" pos:[180,460] width:260 height:30 visible:false
        button btn_n_replace_cancel "CANCEL" pos:[315,460] width:125 height:30 visible:false

        button btn_done_s7 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 8 : PREVIEW
        -- ===========================================================
        listBox lst_log_s8 "" pos:[180,20] width:590 height:12 visible:false
        button btn_prev_fix_s8 "ASSIGN PREVIEW IMAGE" pos:[375,350] width:200 height:80 visible:false
        button btn_done_s8 "VALIDATE ✔" pos:[630,515] width:140 height:60 visible:false

        -- ===========================================================
        -- UI ÉTAPE 9 : KEYWORDS
        -- ===========================================================
        label lbl_cat_s9 "Category:" pos:[-1000,-1000] width:80 height:16 
        dotNetControl cbx_cat "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:200 height:21 
        label lbl_subcat_s9 "Subcat:" pos:[-1000,-1000] width:80 height:16 
        dotNetControl cbx_subcat "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:200 height:21 
        
        button btn_ai_s9 "AI Search" pos:[-1000,-1000] width:100 height:45 
        button btn_done_s9 "SAVE OK FILE" pos:[-1000,-1000] width:150 height:45 
        button btn_final_validate_s9 "FINAL VALIDATE ✔" pos:[-1000,-1000] width:140 height:60

        label lbl_key_s9 "Keywords:" pos:[-1000,-1000] width:590 height:16 
        dotNetControl cbx_k1 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k2 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k3 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k4 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k5 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        
        dotNetControl cbx_k6 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k7 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k8 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k9 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k10 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 

        dotNetControl cbx_k11 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k12 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k13 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k14 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 
        dotNetControl cbx_k15 "System.Windows.Forms.ComboBox" pos:[-1000,-1000] width:180 height:21 

        -- ===========================================================
        -- VARIABLES D'ÉTAT GLOBALES
        -- ===========================================================
        local currentStep   = 1
        local stepStates    = #(0,0,0,0,0,0,0,0,0) 
        local stepNames     = #("Check Corona & Reset", "Check filename", "Check maps", "Check pivots", "Check wirecolor", "Check layers", "Check names", "Check preview", "Check keywords")
        
        local step2_state   = 1
        local cleanedName   = ""
        local wirecolorBackup = #()
        local wirecolorAutoProcessed = false
        local replacePending = false
        local replacePreviewActive = false
        local replacePendingSearch = ""
        local replacePendingReplacement = ""
        local replacePendingTargets = #()
        local replacePreviewOriginalNames = #()

        local step3_state       = 1
        local bitmapList        = #()
        local bitmapList_clean  = #()
        local totalMaps         = 0
        local missingMaps       = 0
        local relativeMaps      = 0
        local emptyMaps         = 0
        local wrongLocationMaps = 0
        local wrongLocationList = #()

        -- ===========================================================
        -- FONCTIONS GLOBALES (UI & NAV)
        -- ===========================================================
        fn updateChecklistUI =
        (
            local labels = #(lbl_step1, lbl_step2, lbl_step3, lbl_step4, lbl_step5, lbl_step6, lbl_step7, lbl_step8, lbl_step9)
            for i = 1 to 9 do
            (
                local prefix = "[   ] "
                if stepStates[i] == 1 then prefix = "[✔] "
                else if i == currentStep then prefix = "[ . ] "
                labels[i].text = prefix + stepNames[i]
            )
            btn_prev.enabled = (currentStep > 1)
            btn_next.enabled = (currentStep < 9)
        )

        fn hideAllUI =
        (
            local allCtrls = #(
                lst_log_s1, grp_prune_s1, chk_removeCameras_s1, chk_removeXRefs_s1, chk_garbage_s1, chk_memory_s1, chk_reactor_s1, chk_animLayers_s1, chk_missingObjects_s1, chk_animKeys_s1, chk_particleView_s1, chk_coronaAssets_s1, chk_rootCA_s1, chk_missingPlugins_s1, chk_junkEffects_s1, btn_main_s1, btn_converter_s1, btn_done_s1, btn_recheck_s1,
                lst_log_s2, lbl_prev_title_s2, edt_before_s2, lbl_arrow_s2, edt_after_s2, btn_main_s2, btn_confirm_s2,
                lst_log_s3, chk_fixOutside_s3, btn_force_s3, btn_copy_local_s3, btn_main_s3, btn_remove_missing_s3, btn_recheck_s3, btn_done_s3,
                lst_log_s4, btn_piv_each_s4, btn_piv_grp_s4, btn_done_s4,
                lst_log_s5, btn_wire_s5, btn_done_s5,
                lst_log_s6, btn_lay_fix_s6, btn_done_s6,
                lbl_n_pref, edt_n_pref, lbl_n_base, edt_n_base, btn_n_all, btn_n_grp, btn_n_sel, lbl_n_search, edt_n_search, lbl_n_repl, edt_n_repl, btn_n_replace, btn_n_replace_cancel, btn_done_s7, lst_names_s7,
                lst_log_s8, btn_prev_fix_s8, btn_done_s8,
                lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15
            )
            for c in allCtrls where c != undefined do try(c.visible = false)catch()
			
			local s9Ctrls = #(lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
			for c in s9Ctrls where c != undefined do try(c.pos = [-1000,-1000])catch()
        )

        fn showCurrentStepUI =
        (
            hideAllUI()
            if currentStep == 1 then (
                for c in #(lst_log_s1, grp_prune_s1, chk_removeCameras_s1, chk_removeXRefs_s1, chk_garbage_s1, chk_memory_s1, chk_reactor_s1, chk_animLayers_s1, chk_missingObjects_s1, chk_animKeys_s1, chk_particleView_s1, chk_coronaAssets_s1, chk_rootCA_s1, chk_missingPlugins_s1, chk_junkEffects_s1) do c.visible = true
                if stepStates[1] == 0 then btn_main_s1.visible = true
            )
            else if currentStep == 2 then ( for c in #(lst_log_s2, lbl_prev_title_s2, edt_before_s2, lbl_arrow_s2, edt_after_s2) do c.visible = true; if step2_state == 2 then btn_confirm_s2.visible = true else btn_main_s2.visible = true )
            else if currentStep == 3 then ( 
                for c in #(lst_log_s3, btn_done_s3) do c.visible = true
                if step3_state == 1 do btn_main_s3.visible = true
                if step3_state >= 2 do btn_force_s3.visible = true
                
                if step3_state == 2 do (
                    btn_main_s3.visible = true
                    if wrongLocationMaps > 0 do (
                        chk_fixOutside_s3.visible = true
                        btn_copy_local_s3.visible = true
                        btn_copy_local_s3.enabled = true
                    )
                )
                if step3_state == 3 do ( -- Manquants après relink
                    btn_remove_missing_s3.visible = true
                    btn_recheck_s3.visible = true
                )
                if step3_state == 4 do btn_main_s3.visible = true -- Affiche le bouton Disabled "ALL OK"
            )
            else if currentStep == 4 then ( for c in #(lst_log_s4, btn_piv_each_s4, btn_piv_grp_s4, btn_done_s4) do c.visible = true )
            
            else if currentStep == 5 then ( 
                lst_log_s5.visible = true
                btn_done_s5.visible = true

                -- La correction est automatique à la première entrée. Les couleurs d'origine sont
                -- conservées pour un Undo ciblé, sans annuler d'autres actions ultérieures de l'utilisateur.
                if not wirecolorAutoProcessed then (
                    local changedCount = 0
                    undo "Auto-fix black wirecolor" on changedCount = wColor()
                    wirecolorAutoProcessed = true
                    if changedCount > 0 do btn_wire_s5.visible = true
                    stepStates[5] = 1
                    updateChecklistUI()
                )
                if wirecolorBackup.count > 0 do btn_wire_s5.visible = true
            )
            
            else if currentStep == 6 then ( for c in #(lst_log_s6, btn_lay_fix_s6, btn_done_s6) do c.visible = true )
            else if currentStep == 7 then ( for c in #(lbl_n_pref, edt_n_pref, lbl_n_base, edt_n_base, btn_n_all, btn_n_grp, btn_n_sel, lbl_n_search, edt_n_search, lbl_n_repl, edt_n_repl, btn_n_replace, btn_done_s7, lst_names_s7) do c.visible = true )
            else if currentStep == 8 then ( for c in #(lst_log_s8, btn_prev_fix_s8, btn_done_s8) do c.visible = true )
            
            else if currentStep == 9 then ( 
                lbl_cat_s9.pos=[180,20]; cbx_cat.pos=[260,19]; lbl_subcat_s9.pos=[180,45]; cbx_subcat.pos=[260,43]
                btn_ai_s9.pos=[480,18]; btn_done_s9.pos=[600,18]; btn_final_validate_s9.pos=[630,515]; lbl_key_s9.pos=[180,80]
                cbx_k1.pos=[180,100]; cbx_k2.pos=[180,125]; cbx_k3.pos=[180,150]; cbx_k4.pos=[180,175]; cbx_k5.pos=[180,200]
                cbx_k6.pos=[380,100]; cbx_k7.pos=[380,125]; cbx_k8.pos=[380,150]; cbx_k9.pos=[380,175]; cbx_k10.pos=[380,200]
                cbx_k11.pos=[580,100]; cbx_k12.pos=[580,125]; cbx_k13.pos=[580,150]; cbx_k14.pos=[580,175]; cbx_k15.pos=[580,200]
                
                for c in #(lbl_cat_s9, cbx_cat, lbl_subcat_s9, cbx_subcat, btn_ai_s9, btn_done_s9, btn_final_validate_s9, lbl_key_s9, cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15) do c.visible = true 
                
                if not step9_Initialized do (
                    initStep9Keywords()
                    step9_Initialized = true
                )
            )

            -- Même si la cascade saute aussi l'étape Layers, la restauration ciblée reste accessible.
            if currentStep >= 6 and wirecolorBackup.count > 0 do btn_wire_s5.visible = true
        )
        -- ===========================================================
        fn collectMaterials mat collected = (
            if mat == undefined then return collected
            if (findItem collected mat) == 0 do (
                append collected mat
                -- Va chercher dans les Multi/Sub-Object
                if superclassof mat == MaterialContainer then (
                    for i = 1 to mat.numsubs do collectMaterials mat[i] collected
                )
            )
            return collected
        )

        fn checkSceneMaterials = (
            local mats = #()
            for o in objects where o.material != undefined do collectMaterials o.material mats
            
            local badMats = #()
            for m in mats do (
                local cStr = classof m as string
                -- Autorise les matériaux Corona, les Multi/Sub-Object et les matériaux généraux Blend.
                -- Blend est un matériau général valide : il ne doit pas déclencher l'alerte Corona.
                if not (matchPattern cStr pattern:"*Corona*") and cStr != "Multimaterial" and cStr != "Multi/Sub-Object" and cStr != "Blend" do (
                    append badMats m
                )
            )
            return badMats
        )

        fn getSystemUnitCentimeters unitType = (
            case unitType of (
                #millimeters: 0.1
                #centimeters: 1.0
                #meters: 100.0
                #kilometers: 100000.0
                #inches: 2.54
                #feet: 30.48
                #miles: 160934.4
                default: undefined
            )
        )

        fn normalizeSceneUnitsToCentimeters logLines = (
            local oldType = units.SystemType
            local oldScale = units.SystemScale
            local typeInCm = getSystemUnitCentimeters oldType
            local scaleFactor = undefined
            append logLines "--- CONTRÔLE DES UNITÉS ---"
            append logLines ("Unités système source : " + (oldType as string) + " (échelle " + (oldScale as string) + ")")

            if typeInCm == undefined then (
                append logLines "ERREUR : unité système non prise en charge. Conversion annulée pour protéger l'échelle."
                return false
            )

            -- Nombre de centimètres représenté par une unité système source.
            scaleFactor = typeInCm * oldScale
            if (abs (scaleFactor - 1.0)) > 0.000001 then (
                append logLines ("Rescale World Units : facteur " + (scaleFactor as string) + " pour préserver les dimensions réelles.")
                try(
                    rescaleWorldUnits scaleFactor
                )catch(
                    append logLines "ERREUR : Rescale World Units a échoué. Aucun Clean Reset n'est lancé."
                    return false
                )
            ) else append logLines "Échelle système déjà équivalente à 1 cm : aucun rescale géométrique requis."

            try(
                units.SystemType = #centimeters
                units.SystemScale = 1.0
                units.DisplayType = #metric
                units.MetricType = #centimeters
            )catch(
                append logLines "ERREUR : impossible d'appliquer les unités système/affichage en centimètres."
                return false
            )

            local verified = false
            try(verified = (units.SystemType == #centimeters and (abs (units.SystemScale - 1.0)) < 0.000001 and units.DisplayType == #metric and units.MetricType == #centimeters))catch()
            if verified then append logLines "✔ Unités validées : système 1 unité = 1 cm, affichage métrique en cm."
            else append logLines "ERREUR : vérification des unités en cm échouée."
            verified
        )

        fn isPluginCleanupCandidate cStr = (
            local low = toLower cStr
            -- Les classes Missing/Unknown sont les placeholders habituels. Les autres motifs sont les
            -- résidus legacy explicitement détectés par Scene Converter et non souhaités dans un asset Corona.
            (matchPattern low pattern:"*missing*") or
            (matchPattern low pattern:"*unknown*") or
            (matchPattern low pattern:"*turbosmooth*pro*") or
            (matchPattern low pattern:"*turbo*pro*") or
            (matchPattern low pattern:"*mental*ray*") or
            (matchPattern low pattern:"mental*") or
            (matchPattern low pattern:"mr_*") or
            (matchPattern low pattern:"*arch*design*")
        )

        fn collectMissingPluginItems = (
            local items = #()
            local mats = #()
            for o in objects do (
                local cStr = classof o as string
                if isPluginCleanupCandidate cStr do append items #(#node, o, cStr)

                -- Avant, les modifiers n'étaient jamais inspectés : TurboSmooth Pro pouvait donc passer inaperçu.
                local mods = #()
                try(for mod in o.modifiers do append mods mod)catch()
                for mod in mods do (
                    local modClass = classof mod as string
                    if isPluginCleanupCandidate modClass do append items #(#modifier, o, mod, modClass)
                )
                if o.material != undefined do collectMaterials o.material mats
            )
            for m in mats do (
                local cStr = classof m as string
                if isPluginCleanupCandidate cStr do append items #(#material, m, cStr)
            )
            items
        )

        fn promptMissingPlugins logLines = (
            if not chk_missingPlugins_s1.checked then return logLines
            local items = collectMissingPluginItems()
            if items.count == 0 then (
                append logLines "Plugins/résidus legacy : aucun Missing/Unknown, TurboSmooth Pro ou Mental Ray détecté."
                return logLines
            )
            local msg = "Plugins/résidus à supprimer détectés :\n\n"
            for item in items do (
                local itemName = ""
                local className = ""
                case item[1] of (
                    #node: (try(itemName = item[2].name)catch(itemName = "[objet]"); className = item[3])
                    #material: (try(itemName = item[2].name)catch(itemName = "[matériau]"); className = item[3])
                    #modifier: (try(itemName = item[2].name + "  >  " + item[3].name)catch(itemName = "[modifier]"); className = item[4])
                )
                msg += "• " + className + " — " + itemName + "\n"
            )
            msg += "\nSupprimer ces éléments ?\nCette action peut modifier les matériaux, objets ou le rendu."
            if queryBox msg title:"Iconia — Plugins / résidus legacy" then (
                local removed = 0
                for item in items do (
                    case item[1] of (
                        #node: try(delete item[2]; removed += 1)catch()
                        #material: for o in objects where o.material == item[2] do try(o.material = undefined; removed += 1)catch()
                        #modifier: try(deleteModifier item[2] item[3]; removed += 1)catch()
                    )
                )
                append logLines ("Plugins/résidus détectés : " + (items.count as string) + ". Suppression confirmée : " + (removed as string) + " élément(s).")
            ) else append logLines ("Plugins/résidus détectés : " + (items.count as string) + ". Action utilisateur : conservés.")
            logLines
        )

        fn removeCamerasForAsset = (
            local count = 0
            for c in cameras do try(delete c; count += 1)catch()
            count
        )

        fn removeXRefsForAsset = (
            local targets = #()
            for o in objects do if matchPattern (classof o as string) pattern:"*XRef*" ignoreCase:true do append targets o
            for o in targets do try(delete o)catch()
            targets.count
        )

        fn removeEmptyOrMissingObjects = (
            local targets = #()
            for o in objects do (
                local cStr = classof o as string
                local isMissing = (matchPattern cStr pattern:"*Missing*" ignoreCase:true) or (matchPattern cStr pattern:"*Unknown*" ignoreCase:true)
                local isEmptyGeometry = false
                if superclassof o == GeometryClass do (
                    try (
                        local polyCount = getPolygonCount o
                        isEmptyGeometry = (polyCount[1] == 0 and polyCount[2] == 0)
                    ) catch()
                )
                if isMissing or isEmptyGeometry do append targets o
            )
            for o in targets do try(delete o)catch()
            targets.count
        )

        fn removeParticleViewObjects = (
            local targets = #()
            for o in objects where matchPattern o.name pattern:"Particle_View_*" ignoreCase:true do (
                local isEmpty = true
                try (
                    local polyCount = getPolygonCount o
                    isEmpty = (polyCount[1] == 0 and polyCount[2] == 0)
                ) catch()
                if isEmpty do append targets o
            )
            for o in targets do try(delete o)catch()
            targets.count
        )

        fn removeAnimationKeysForAsset = (
            local count = 0
            for o in objects do (
                try (
                    if (numKeys o) > 0 do (
                        deleteKeys o
                        count += 1
                    )
                ) catch()
            )
            count
        )

        fn removeAnimationLayersForAsset = (
            local removed = 0
            try (
                removed = maxOps.numAnimationLayers
                if removed > 0 do maxOps.deleteAllAnimationLayers()
            ) catch()
            removed
        )

        fn removeMissingCoronaAssets = (
            local count = 0
            local bitmaps = #()
            try(bitmaps = getClassInstances Bitmaptexture)catch()
            for b in bitmaps do (
                try (
                    local f = b.filename
                    local fLow = toLower f
                    if f != "" and not doesFileExist f and ((matchPattern fLow pattern:"*.hdc") or (matchPattern fLow pattern:"*.cube")) do (
                        b.filename = ""
                        count += 1
                    )
                ) catch()
            )
            count
        )

        fn removeRootCustomAttributes = (
            local knownNames = #("day1RefCA", "D1_FileNotes", "NoteCount")
            local count = 0
            local i = 0
            try(i = custAttributes.count rootNode)catch()
            while i > 0 do (
                local ca = undefined
                local caName = ""
                try(ca = custAttributes.get rootNode i)catch()
                try(caName = ca.name as string)catch()
                if (findItem knownNames caName) > 0 do try(custAttributes.delete rootNode i; count += 1)catch()
                i -= 1
            )
            count
        )

        fn removeJunkEffects = (
            local count = 0
            try (
                if numEffects > 5 do for i = numEffects to 1 by -1 do ( deleteEffect i; count += 1 )
            ) catch()
            count
        )

        fn runPruneOptions logLines = (
            append logLines "--- PRUNE / CLEAN REPORT ---"
            if chk_removeCameras_s1.checked do append logLines ("Cameras supprimées : " + (removeCamerasForAsset() as string))
            if chk_removeXRefs_s1.checked do append logLines ("XRefs supprimées : " + (removeXRefsForAsset() as string))
            if chk_animLayers_s1.checked do append logLines ("Animation layers supprimées : " + (removeAnimationLayersForAsset() as string))
            if chk_animKeys_s1.checked do append logLines ("Contrôleurs avec clés supprimées : " + (removeAnimationKeysForAsset() as string))
            if chk_particleView_s1.checked do append logLines ("Particle View invalides supprimés : " + (removeParticleViewObjects() as string))
            if chk_missingObjects_s1.checked do append logLines ("Objets manquants / géométries vides supprimés : " + (removeEmptyOrMissingObjects() as string))
            if chk_coronaAssets_s1.checked do append logLines ("Assets Corona inexistants supprimés : " + (removeMissingCoronaAssets() as string))
            if chk_rootCA_s1.checked do append logLines ("Root Custom Attributes connus supprimés : " + (removeRootCustomAttributes() as string))
            if chk_junkEffects_s1.checked do append logLines ("Junk effects supprimés (seuil > 5) : " + (removeJunkEffects() as string))
            if chk_reactor_s1.checked do append logLines "Reactor Collision : aucun nettoyage requis ou API legacy indisponible."
            if chk_memory_s1.checked do (
                try(clearUndoBuffer(); append logLines "Undo Buffer purgé.")catch(append logLines "Undo Buffer : purge non disponible.")
                try(freeSceneBitmaps(); append logLines "Bitmap cache libéré.")catch(append logLines "Bitmap cache : libération non disponible.")
            )
            if chk_garbage_s1.checked do try(gc(); append logLines "Garbage Collector exécuté.")catch(append logLines "Garbage Collector : exécution non disponible.")
            logLines
        )

        fn validateCleanScene logLines = (
            local valid = true
            append logLines "--- VALIDATION POST-CLEAN ---"
            append logLines ("Objets restants : " + (objects.count as string))
            if objects.count == 0 then (
                append logLines "ERREUR : Scène vide après nettoyage."
                valid = false
            )
            local currRend = classOf renderers.current as string
            local isCorona = matchPattern currRend pattern:"*Corona*" ignoreCase:true
            append logLines ("Renderer après nettoyage : " + currRend)
            if not isCorona then (
                append logLines "ERREUR : Corona n'est plus le moteur actif après nettoyage."
                valid = false
            )
            local badMats = checkSceneMaterials()
            append logLines ("Matériaux invalides après nettoyage : " + (badMats.count as string))
            if badMats.count > 0 do valid = false
            valid
        )

        fn doCleanReset = (
            local dir = maxFilePath
            local name = getFilenameFile maxFileName
            local backupPath = dir + name + "_preclean.max"
            local tempExport = dir + name + "_CLEAN.max"
            local logLines = lst_log_s1.items
            local objectCountBefore = objects.count

            -- Le backup est normalement créé avant le popup Missing Plugins ; ce fallback couvre la validation manuelle.
            if not doesFileExist backupPath then (
                if not (saveMaxFile backupPath quiet:true) then (
                    append logLines "ERREUR : Impossible de créer le backup pré-nettoyage."
                    lst_log_s1.items = logLines
                    return false
                )
                append logLines ("Backup pré-nettoyage conservé : " + backupPath)
            ) else append logLines ("Backup pré-nettoyage utilisé : " + backupPath)
            logLines = runPruneOptions logLines
            append logLines ("Objets avant / après prune : " + (objectCountBefore as string) + " / " + (objects.count as string))
            lst_log_s1.items = logLines

            max select all
            if selection.count == 0 then (
                append logLines "ERREUR : Aucun objet sélectionnable à exporter. Restauration du backup."
                lst_log_s1.items = logLines
                loadMaxFile backupPath quiet:true useFileUnits:true
                return false
            )
            saveNodes selection tempExport quiet:true

            if loadMaxFile tempExport quiet:true useFileUnits:true then (
                local isValid = validateCleanScene logLines
                if isValid then (
                    saveMaxFile (dir + name + ".max") quiet:true
                    if doesFileExist tempExport do deleteFile tempExport
                    append logLines "✔ Clean Reset effectué avec succès !"
                    append logLines ("Backup conservé : " + backupPath)
                    lst_log_s1.items = logLines
                    completeStep1()
                ) else (
                    append logLines "ERREUR : Validation post-clean échouée. Restauration du backup..."
                    lst_log_s1.items = logLines
                    loadMaxFile backupPath quiet:true useFileUnits:true
                )
            ) else (
                append logLines "ERREUR : Impossible de recharger la scène nettoyée. Restauration du backup..."
                lst_log_s1.items = logLines
                loadMaxFile backupPath quiet:true useFileUnits:true
            )
        )

        fn doCheckCorona = (
            if maxFilePath == "" then (
                lst_log_s1.items = #("ERROR : File not saved yet.", "Sauvegardez d'abord la scène .max.")
                btn_main_s1.visible = true
                return false
            )

            local logLines = #()
            local currRend = classOf renderers.current as string
            append logLines ("Moteur de rendu actuel : " + currRend)
            
            local isCorona = matchPattern currRend pattern:"*Corona*" ignoreCase:true
            
            if not isCorona then ( 
                append logLines "⚠ ATTENTION : Le moteur n'est PAS Corona !"
                append logLines "Veuillez ouvrir le Corona Converter, convertir la scène,"
                append logLines "puis cliquer sur 'RECHECK'."
                lst_log_s1.items = logLines
                btn_main_s1.visible = false
                btn_converter_s1.visible = true
                btn_done_s1.visible = true
                btn_recheck_s1.visible = true
                return false
            )
            
            append logLines "✔ Moteur Corona détecté."

            -- Backup créé avant toute suppression interactive (plugins manquants compris).
            local originalScenePath = maxFilePath + maxFileName
            local precleanBackupPath = maxFilePath + (getFilenameFile maxFileName) + "_preclean.max"
            if not (saveMaxFile precleanBackupPath quiet:true) then (
                append logLines "ERREUR : Impossible de créer le backup pré-nettoyage."
                lst_log_s1.items = logLines
                return false
            )
            -- saveMaxFile vers un autre chemin peut changer le fichier courant : on ré-enregistre donc immédiatement l'original.
            if not (saveMaxFile originalScenePath quiet:true) then (
                append logLines "ERREUR : Backup créé, mais impossible de restaurer le fichier courant."
                lst_log_s1.items = logLines
                return false
            )
            append logLines ("Backup pré-nettoyage conservé : " + precleanBackupPath)

            -- Normalisation obligatoire avant tout nettoyage : la sauvegarde préclean permet un retour sûr si elle échoue.
            if not (normalizeSceneUnitsToCentimeters logLines) then (
                append logLines "Restauration du backup pré-nettoyage après échec de normalisation des unités..."
                lst_log_s1.items = logLines
                loadMaxFile precleanBackupPath quiet:true useFileUnits:true
                return false
            )

            -- Les résidus Missing/Unknown sont proposés à l'utilisateur avant le contrôle des matériaux.
            logLines = promptMissingPlugins logLines
            
            local badMats = checkSceneMaterials()
            if badMats.count > 0 then (
                append logLines ""
                append logLines "⚠ MATÉRIAUX INVALIDE TROUVÉS :"
                for m in badMats do append logLines (" - " + m.name + " (" + (classof m as string) + ")")
                append logLines "Convertissez ou supprimez ces matériaux avant de continuer."
                lst_log_s1.items = logLines
                btn_main_s1.visible = false
                btn_converter_s1.visible = true
                btn_done_s1.visible = true
                btn_recheck_s1.visible = true
                return false
            )
            
            append logLines "✔ Tous les matériaux sont compatibles Corona."
            append logLines "Lancement du Clean Reset..."
            lst_log_s1.items = logLines
            
            doCleanReset()
        )

        fn completeStep1 = ( 
            stepStates[1] = 1; updateChecklistUI()
            btn_converter_s1.visible = false; btn_done_s1.visible = false; btn_main_s1.visible = false; btn_recheck_s1.visible = false
            switchStep 2
        )

        -- ===========================================================
        -- FONCTIONS ÉTAPE 2 : FILENAME
        -- ===========================================================
        fn cleanMaxFileName rawName = ( 
            local s = rawName
            local hasCorona = false
            local sLow = toLower s
            
            if (findString sLow "corona") != undefined then hasCorona = true
            
            for crPat in #("_cr", "-cr") do (
                local searchIn = sLow
                local pos = findString searchIn crPat
                while pos != undefined do (
                    local afterPos = pos + crPat.count
                    local charAfter = if afterPos <= searchIn.count then substring searchIn afterPos 1 else ""
                    if charAfter == "" or charAfter == "_" or charAfter == "-" or charAfter == " " or (charAfter >= "0" and charAfter <= "9") then hasCorona = true
                    -- Avance en tronquant la string pour simuler une recherche à partir de pos+1
                    if pos < searchIn.count then searchIn = substring searchIn (pos + 1) -1 else searchIn = ""
                    pos = findString searchIn crPat
                )
            )
            
            fn removeYear str = (
                local result = str
                local i = 1
                while i <= result.count do (
                    local c = substring result i 1
					local isSep  = (c == "_" or c == "-" or c == " " or c == "{" or c == "[" or c == "(" or c == ".")
					local isAlph = ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z"))
                    
                    if (isSep or isAlph) and (i + 4 <= result.count) then (
                        local d1 = substring result (i+1) 1
                        local d2 = substring result (i+2) 1
                        local d3 = substring result (i+3) 1
                        local d4 = substring result (i+4) 1
                        local isYear = ((d1 == "1" and d2 == "9") or (d1 == "2" and d2 == "0")) \
                                       and (d3 >= "0" and d3 <= "9") and (d4 >= "0" and d4 <= "9")
                        
                        if isYear then (
                            local after = if (i + 5) <= result.count then (substring result (i+5) 1) else ""
                            local isEnd = (after == "" or after == "_" or after == "-" or after == " " or after == "}" or after == "]" or after == ")")
                            
                            if isEnd then (
                                local startIdx = if isSep then (i - 1 + 1) else i
                                local before = if isSep then (substring result 1 (i-1)) else (substring result 1 i)
                                local rest   = if (i + 4) < result.count then (substring result (i+5) -1) else ""
                                result = before + rest
                            ) else ( i += 1 )
                        ) else ( i += 1 )
                    ) else ( i += 1 )
                )
                return result
            )
            
            s = removeYear s
            
            local coronarenderVariants = #("_CoronaRender", "-CoronaRender", " CoronaRender", "(CoronaRender)", "_coronarender", "-coronarender", " coronarender", "(coronarender)", "_CORONARENDER", "-CORONARENDER", " CORONARENDER", "(CORONARENDER)", "CoronaRender", "coronarender", "CORONARENDER")
            for v in coronarenderVariants do s = substituteString s v ""
            local coronaVariants = #("(Corona)", "(corona)", "(CORONA)", "_Corona",  "-Corona",  " Corona", "_corona",  "-corona",  " corona", "_CORONA",  "-CORONA",  " CORONA", "Corona",   "corona",   "CORONA")
            for v in coronaVariants do s = substituteString s v ""
            -- Suppression de _CR / -CR uniquement quand précédé d'un séparateur
            -- et suivi d'un séparateur, chiffre ou fin de chaîne (évite "cream", "across"…)
            fn removeCRtag str = (
                local result = str
                local sLow2  = toLower result
                local pat    = undefined
                for p in #("_cr", "-cr") do (
                    local searchIn = sLow2
                    local offset   = 0
                    local pos = findString searchIn p
                    while pos != undefined do (
                        local realPos  = offset + pos
                        local afterPos = realPos + p.count
                        local charAfter = if afterPos <= result.count then (toLower (substring result afterPos 1)) else ""
                        local isSafeAfter = (charAfter == "" or charAfter == "_" or charAfter == "-" or charAfter == " " or (charAfter >= "0" and charAfter <= "9"))
                        if isSafeAfter then (
                            result  = (if realPos > 1 then substring result 1 (realPos - 1) else "") + (if afterPos <= result.count then substring result afterPos -1 else "")
                            sLow2   = toLower result
                            offset  = 0
                            searchIn = sLow2
                        ) else (
                            offset   += pos
                            searchIn  = substring sLow2 (offset + 1) -1
                        )
                        pos = findString searchIn p
                    )
                )
                return result
            )
            s = removeCRtag s
            -- Suppression de "Copie" / "copie" en fin de nom (avec ou sans " - " avant)
            local copieVariants = #(" - Copie", " - copie", "-Copie", "-copie", "_Copie", "_copie", " Copie", " copie", "Copie", "copie")
            for v in copieVariants do (
                if s.count >= v.count do (
                    local tail = substring s (s.count - v.count + 1) v.count
                    if (stricmp tail v == 0) do s = substring s 1 (s.count - v.count)
                )
            )
            local vrayVariants = #("_V-ray", "-V-ray", " V-ray", "(V-ray)", "_v-ray", "-v-ray", " v-ray", "(v-ray)", "_V-Ray", "-V-Ray", " V-Ray", "(V-Ray)", "V-ray", "v-ray", "V-Ray", "_VRay", "-VRay", " VRay", "(VRay)", "_vray", "-vray", " vray", "(vray)", "_VRAY", "-VRAY", " VRAY", "(VRAY)", "_Vray", "-Vray", " Vray", "(Vray)", "_VRayMtl","-VRayMtl"," VRayMtl", "VRay", "vray", "VRAY", "Vray")
            for v in vrayVariants do s = substituteString s v ""
            -- Un millésime collé à un tag moteur (ex. _2015vray) ne pouvait pas être reconnu
            -- au premier passage. Après retrait de V-Ray/Corona, on repasse donc le filtre année.
            s = removeYear s
            
            local prevS = ""
            while prevS != s do ( prevS = s; s = substituteString s "__" "_" )
            prevS = ""
            while prevS != s do ( prevS = s; s = substituteString s "--" "-" )
            while s.count > 0 do ( local last = substring s s.count 1; if last == "_" or last == "-" or last == " " or last == "}" or last == "]" or last == ")" then s = substring s 1 (s.count - 1) else exit )
			while s.count > 0 do ( local first = substring s 1 1; if first == "_" or first == "-" or first == " " or first == "{" or first == "[" or first == "(" then s = substring s 2 -1 else exit )
            
            if hasCorona then s = s + "_corona"
            return #(s, hasCorona)
        )

        fn doRenameOnDisk oldPath newBaseName = (
            local dir = getFilenamePath oldPath; local oldExt = getFilenameType oldPath; local newPath = dir + newBaseName + oldExt
            local isExactSame = (oldPath.count == newPath.count and matchPattern oldPath pattern:newPath ignoreCase:false)
            if isExactSame then return #(true, "unchanged")
            if (toLower oldPath) == (toLower newPath) then ( local tempPath = dir + newBaseName + "_TEMP" + oldExt; renameFile oldPath tempPath; if (renameFile tempPath newPath) then return #(true, newPath) else return #(false, "Case-only rename failed.") )
            if doesFileExist newPath then return #(false, "A file with that name already exists:\n" + newPath)
            if (renameFile oldPath newPath) then return #(true, newPath) else return #(false, "renameFile failed.")
        )

        fn completeStep2 = ( 
            stepStates[2] = 1; updateChecklistUI(); 
            btn_confirm_s2.visible = false; btn_main_s2.visible = true; btn_main_s2.enabled = false; btn_main_s2.text = "RENAME\nDONE ✔"; step2_state = 3 
            switchStep 3
        )

        fn doCheckFilename = (
            if maxFileName == "" then ( lst_log_s2.items = #("ERROR : File not saved yet.", "Please save your .max file first, then click RETRY."); btn_main_s2.visible = true; btn_main_s2.enabled = true; return false )
            local rawBase = getFilenameFile maxFileName; local result = cleanMaxFileName rawBase; cleanedName = result[1]; local hasCoronaFlag = result[2]
            local logLines = #(); append logLines ("File   : " + maxFileName); append logLines ("Path   : " + maxFilePath); append logLines ""
            local rawLow = toLower rawBase
            if (findString rawLow "vray") != undefined or (findString rawLow "v-ray") != undefined then append logLines "⚠  VRay/V-ray detected → will be removed"
            if hasCoronaFlag then append logLines "✓  Corona detected → will become _corona suffix"
            local hasYear = false
            for yearSep in #("_", "-", " ") do ( for yearPfx in #("19", "20") do ( local yp = findString rawBase (yearSep + yearPfx); if yp != undefined and (yp + 4) <= rawBase.count do hasYear = true ) )
            if hasYear then append logLines "✓  Year detected → will be removed"
            local isAlreadyClean = (cleanedName.count == rawBase.count and matchPattern cleanedName pattern:rawBase ignoreCase:false)
            if isAlreadyClean then ( 
                append logLines ""; append logLines "✔  Filename is already clean. Nothing to do."
                lst_log_s2.items = logLines; edt_before_s2.text = rawBase; edt_after_s2.text = cleanedName
                completeStep2()
                return true 
            )
            append logLines ""; append logLines "Review the rename below, then confirm."; lst_log_s2.items = logLines; edt_before_s2.text = rawBase; edt_after_s2.text = cleanedName; btn_main_s2.visible = false; btn_confirm_s2.visible = true; step2_state = 2
        )

        -- ===========================================================
        -- FONCTIONS ÉTAPE 3 : MAPS
        -- ===========================================================
        fn collectAllBitmaps =
        (
            bitmapList       = #()
            bitmapList_clean = #()
            local lists = #()
            try( join lists (getClassInstances BitmapTexture) )catch()
            try( join lists (getClassInstances CoronaBitmap)  )catch()
            try( join lists (getClassInstances VRayBitmap)    )catch()

            for b in lists do (
                local fname = ""
                try( fname = b.filename )catch()
                if fname != undefined and fname != "" then (
                    appendIfUnique bitmapList b
                    appendIfUnique bitmapList_clean fname
                )
            )
            sort bitmapList_clean
            return bitmapList_clean
        )

        fn checkBitmapStatus b =
        (
            local fname = ""
            try( fname = b.filename )catch()
            if fname == undefined or fname == "" then return "EMPTY"
            if not (pathConfig.isAbsolutePath fname) then return "RELATIVE"
            if not (doesFileExist fname) then return "MISSING"
            return "OK"
        )

        fn findMapInProject fNameOnly =
        (
            local scenePath = maxFilePath
            if scenePath == "" or fNameOnly == "" then return ""

            -- Priorité explicite : maps/map/textures/texture, puis racine, puis tous les sous-dossiers.
            local priorityFolders = #("maps", "map", "textures", "texture")
            for sub in priorityFolders do (
                local directPath = scenePath + sub + "\\" + fNameOnly
                if doesFileExist directPath do return directPath
            )
            local rootPath = scenePath + fNameOnly
            if doesFileExist rootPath do return rootPath

            local Directory = dotNetClass "System.IO.Directory"
            local SearchOption = dotNetClass "System.IO.SearchOption"
            local foundFiles = undefined
            try(foundFiles = Directory.GetFiles scenePath fNameOnly SearchOption.AllDirectories)catch()
            -- Directory.GetFiles est converti en Array MAXScript (#(...)) : utiliser la propriété Array .count, pas .Length.
            -- La fonction globale count est masquée dans ce rollout par une variable locale nommée count.
            if foundFiles != undefined and foundFiles.count > 0 do return foundFiles[1]
            ""
        )

        fn relinkBitmaps doFixOutside =
        (
            local scenePath  = maxFilePath
            local fixedCount = 0
            local missingCount = 0

            if scenePath == "" then (
                messageBox "Veuillez d'abord sauvegarder votre scène (.max)." title:"MaxStack - Relink"
                return #(0,0)
            )

            collectAllBitmaps()
            for bmp in bitmapList do (
                local fname = ""
                try( fname = bmp.filename )catch()
                if fname == undefined or fname == "" then continue

                local isAbs = pathConfig.isAbsolutePath fname
                local isExisting = doesFileExist fname
                local isOutside = false
                if isAbs and isExisting do (
                    if (findString (toLower fname) (toLower scenePath)) == undefined do isOutside = true
                )

                if not isAbs or not isExisting or (doFixOutside and isOutside) then (
                    local foundPath = findMapInProject (filenameFromPath fname)
                    if foundPath != "" then (
                        if (toLower fname) != (toLower foundPath) do (
                            try(bmp.filename = foundPath; fixedCount += 1)catch()
                        )
                    ) else if not isAbs or not isExisting do missingCount += 1
                )
            )
            try(atsops.refresh())catch()
            #(fixedCount, missingCount)
        )

        fn moveProjectMapsToCanonicalFolder =
        (
            local scenePath = maxFilePath
            if scenePath == "" then return #(0,0,0,false)
            local targetFolder = scenePath + "maps\\"
            local Directory = dotNetClass "System.IO.Directory"
            if not (Directory.Exists targetFolder) do Directory.CreateDirectory targetFolder
            if not (Directory.Exists targetFolder) then return #(0,0,0,false)

            collectAllBitmaps()
            local sources = #()
            local sceneLow = toLower scenePath
            local targetLow = toLower targetFolder
            for b in bitmapList do (
                local fname = ""
                try(fname = b.filename)catch()
                if fname != undefined and fname != "" and (pathConfig.isAbsolutePath fname) and (doesFileExist fname) do (
                    local fLow = toLower fname
                    -- On ne déplace que les fichiers appartenant déjà au projet et hors du dossier /maps canonique.
                    if (findString fLow sceneLow) == 1 and (findString fLow targetLow) != 1 do appendIfUnique sources fname
                )
            )
            if sources.count == 0 then return #(0,0,0,false)

            -- Les sources appartiennent au dossier de l'asset : l'affichage relatif évite de répéter
            -- une racine très longue sur chaque ligne, sans modifier les chemins réellement déplacés.
            local nl = (bit.intAsChar 13) + (bit.intAsChar 10)
            local msg = "Maps détectées hors du dossier de l'asset /maps :" + nl + nl
            for src in sources do (
                local displaySrc = src
                if (findString (toLower src) sceneLow) == 1 then (
                    local relativeStart = scenePath.count + 1
                    if relativeStart <= src.count then displaySrc = "\\" + (substring src relativeStart -1)
                    else displaySrc = "\\"
                )
                msg += displaySrc + nl
            )
            msg += nl + "Déplacer ces fichiers dans :" + nl + "\\maps\\ ?"

            -- queryBox est trop étroit et replie les chemins. Fenêtre large, scrollable et sans retour à la ligne.
            local form = dotNetObject "System.Windows.Forms.Form"
            local panel = dotNetObject "System.Windows.Forms.Panel"
            local pathsBox = dotNetObject "System.Windows.Forms.TextBox"
            local yesButton = dotNetObject "System.Windows.Forms.Button"
            local noButton = dotNetObject "System.Windows.Forms.Button"
            local DockStyle = dotNetClass "System.Windows.Forms.DockStyle"
            local ScrollBars = dotNetClass "System.Windows.Forms.ScrollBars"
            local DialogResult = dotNetClass "System.Windows.Forms.DialogResult"

            form.Text = "Iconia — Move maps to /maps"
            form.Width = 1200
            form.Height = 560
            form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
            form.MinimizeBox = false
            form.MaximizeBox = true
            form.ShowInTaskbar = false

            pathsBox.Multiline = true
            pathsBox.ReadOnly = true
            pathsBox.WordWrap = false
            pathsBox.ScrollBars = ScrollBars.Both
            pathsBox.Dock = DockStyle.Fill
            pathsBox.Text = msg

            panel.Dock = DockStyle.Bottom
            panel.Height = 52
            yesButton.Text = "Déplacer vers /maps"
            yesButton.Width = 180
            yesButton.Height = 28
            -- Groupe de boutons centré dans la largeur utile de la fenêtre.
            yesButton.Left = 395
            yesButton.Top = 10
            yesButton.DialogResult = DialogResult.Yes
            noButton.Text = "Conserver les emplacements"
            noButton.Width = 210
            noButton.Height = 28
            noButton.Left = 587
            noButton.Top = 10
            noButton.DialogResult = DialogResult.No
            panel.Controls.Add yesButton
            panel.Controls.Add noButton
            form.Controls.Add pathsBox
            form.Controls.Add panel
            form.AcceptButton = yesButton
            form.CancelButton = noButton

            local shouldMove = ((form.ShowDialog()) == DialogResult.Yes)
            form.Dispose()
            if not shouldMove then return #(sources.count,0,0,false)

            local moved = 0
            local failed = 0
            for src in sources do (
                local dest = targetFolder + (filenameFromPath src)
                if (toLower src) != (toLower dest) then (
                    if doesFileExist dest do dest = getUniqueLocalFile dest
                    if renameFile src dest then (
                        for b in bitmapList do try(if (stricmp b.filename src) == 0 do b.filename = dest)catch()
                        moved += 1
                    ) else failed += 1
                )
            )
            try(atsops.refresh())catch()
            #(sources.count,moved,failed,true)
        )

        fn getLocalMapsFolder =
        (
            local scenePath = maxFilePath
            if scenePath == "" then return ""

            -- /maps est le dossier canonique Iconia, y compris si une ancienne scène contient /textures.
            local Directory = dotNetClass "System.IO.Directory"
            local newFolder = scenePath + "maps\\"
            if not (Directory.Exists newFolder) do Directory.CreateDirectory newFolder
            if Directory.Exists newFolder then newFolder else ""
        )

        fn getUniqueLocalFile basePath =
        (
            if not (doesFileExist basePath) then return basePath

            local folder = getFilenamePath basePath
            local baseName = getFilenameFile basePath
            local ext = getFilenameType basePath
            local idx = 1
            local testPath = folder + baseName + "_" + (idx as string) + ext

            while doesFileExist testPath do (
                idx += 1
                testPath = folder + baseName + "_" + (idx as string) + ext
            )
            return testPath
        )

        fn copyOutsideMapsToLocal =
        (
            local scenePath = maxFilePath
            if scenePath == "" then (
                messageBox "Veuillez d'abord sauvegarder votre scene (.max)." title:"MaxStack - Copy Maps"
                return false
            )

            local targetFolder = getLocalMapsFolder()
            if targetFolder == "" then (
                messageBox "Impossible de trouver ou creer un dossier maps/textures local." title:"MaxStack - Copy Maps"
                return false
            )

            collectAllBitmaps()

            local copiedCount = 0
            local reusedCount = 0
            local failedCount = 0
            local copiedSources = #()
            local copiedTargets = #()
            local logLines = #()
            local sceneLow = toLower scenePath

            append logLines ("Copy maps to local folder:")
            append logLines targetFolder
            append logLines ""

            for b in bitmapList do (
                local fname = ""
                try( fname = b.filename )catch()

                if fname != undefined and fname != "" and (pathConfig.isAbsolutePath fname) and (doesFileExist fname) then (
                    local fLow = toLower fname
                    local isOutside = ((findString fLow sceneLow) == undefined)

                    if isOutside then (
                        local existingIdx = 0
                        for i = 1 to copiedSources.count where (stricmp copiedSources[i] fname == 0) do (
                            existingIdx = i
                            exit
                        )

                        local destPath = ""
                        if existingIdx > 0 then (
                            destPath = copiedTargets[existingIdx]
                            reusedCount += 1
                        ) else (
                            destPath = targetFolder + (filenameFromPath fname)
                            if doesFileExist destPath then destPath = getUniqueLocalFile destPath

                            if copyFile fname destPath then (
                                append copiedSources fname
                                append copiedTargets destPath
                                copiedCount += 1
                                append logLines ("  copied: " + (filenameFromPath fname))
                            ) else (
                                failedCount += 1
                                append logLines ("  failed: " + (filenameFromPath fname))
                                destPath = ""
                            )
                        )

                        if destPath != "" do try( b.filename = destPath )catch()
                    )
                )
            )

            atsops.refresh()

            append logLines ""
            append logLines ("Copied             : " + copiedCount as string)
            append logLines ("Reused duplicates  : " + reusedCount as string)
            append logLines ("Failed             : " + failedCount as string)
            lst_log_s3.items = logLines

            doStep3_Scan()
            return (failedCount == 0)
        )

        fn doStep3_Scan =
        (
            collectAllBitmaps()
            totalMaps         = bitmapList.count
            missingMaps       = 0
            relativeMaps      = 0
            emptyMaps         = 0
            wrongLocationMaps = 0
            wrongLocationList = #()

            local logLines = #()
            local scenePath = toLower maxFilePath

            for b in bitmapList do (
                local st = checkBitmapStatus b
                case st of (
                    "MISSING":  ( missingMaps  += 1 )
                    "RELATIVE": ( relativeMaps += 1 )
                    "EMPTY":    ( emptyMaps    += 1 )
                    "OK": (
                        local fname = ""
                        try( fname = b.filename )catch()
                        if fname != undefined and fname != "" and scenePath != "" then (
                            local fLow = toLower fname
                            if (findString fLow scenePath) == undefined then (
                                wrongLocationMaps += 1
                                appendIfUnique wrongLocationList (filenameFromPath fname)
                            )
                        )
                    )
                )
            )

            local okMaps = totalMaps - missingMaps - relativeMaps - emptyMaps
            append logLines "Recherche auto : maps/map/textures/texture, racine, puis tous les sous-dossiers."
            append logLines ""
            append logLines ("Total bitmaps found  : " + totalMaps as string)
            append logLines ("OK, in project folder: " + (okMaps - wrongLocationMaps) as string)
            append logLines ("Missing              : " + missingMaps  as string)
            append logLines ("Relative paths       : " + relativeMaps as string)
            append logLines ("Empty paths          : " + emptyMaps    as string)

            if wrongLocationMaps > 0 then (
                append logLines ("Outside project      : " + wrongLocationMaps as string + "  ⚠")
                append logLines ""
                append logLines "--- Maps outside project folder ---"
                for f in wrongLocationList do append logLines ("  ! " + f)
            ) else append logLines ("Outside project      : 0")

            if totalMaps == 0 then (
                append logLines ""
                append logLines "No bitmaps in scene. Étape validée automatiquement."
                lst_log_s3.items = logLines
                step3_state = 4
                if currentStep == 3 then completeStep3() else showCurrentStepUI()
                return true
            )

            -- Toute map Missing ou Relative déclenche immédiatement le relink récursif.
            if (missingMaps + relativeMaps) > 0 then (
                append logLines ""
                append logLines "Missing/Relative détectées : relink automatique en cours..."
                lst_log_s3.items = logLines
                doStep3_Relink()
                return false
            )

            lst_log_s3.items = logLines
            if (emptyMaps + wrongLocationMaps) == 0 then (
                local moveResult = moveProjectMapsToCanonicalFolder()
                if moveResult[1] > 0 then (
                    logLines = lst_log_s3.items
                    append logLines ("Maps hors /maps détectées : " + (moveResult[1] as string))
                    if moveResult[4] then append logLines ("Maps déplacées vers /maps : " + (moveResult[2] as string) + " | Échecs : " + (moveResult[3] as string)) else append logLines "Déplacement vers /maps refusé par l'utilisateur."
                    lst_log_s3.items = logLines
                )
                append logLines "Toutes les maps sont valides. Étape validée automatiquement."
                lst_log_s3.items = logLines
                step3_state = 4
                if currentStep == 3 then completeStep3() else showCurrentStepUI()
                return true
            ) else (
                step3_state = 2
                btn_main_s3.text = "RELINK\nMAPS"
                btn_force_s3.enabled = true
                showCurrentStepUI()
                return false
            )
        )

        fn doStep3_Relink =
        (
            local logLines = lst_log_s3.items
            append logLines ""
            append logLines "Auto-relinking..."
            lst_log_s3.items = logLines

            local result = relinkBitmaps (chk_fixOutside_s3.checked)
            local fixedCount   = result[1]
            local missingCount = result[2]

            collectAllBitmaps()
            local stillInvalid = 0
            local stillOutside = 0
            local scenePath = toLower maxFilePath
            for b in bitmapList do (
                local st = checkBitmapStatus b
                if st == "MISSING" or st == "RELATIVE" or st == "EMPTY" then stillInvalid += 1
                else if st == "OK" and scenePath != "" do (
                    local fname = ""
                    try( fname = b.filename )catch()
                    if fname != undefined and fname != "" do if (findString (toLower fname) scenePath) == undefined do stillOutside += 1
                )
            )

            logLines = #()
            append logLines ("Maps relinked / fixed : " + fixedCount as string)
            append logLines ("Still missing / relative / empty : " + stillInvalid as string)
            if stillOutside > 0 do append logLines ("Still outside project  : " + stillOutside as string)
            append logLines ""

            if stillInvalid == 0 and stillOutside == 0 then (
                local moveResult = moveProjectMapsToCanonicalFolder()
                if moveResult[1] > 0 then (
                    append logLines ("Maps hors /maps détectées : " + (moveResult[1] as string))
                    if moveResult[4] then append logLines ("Maps déplacées vers /maps : " + (moveResult[2] as string) + " | Échecs : " + (moveResult[3] as string)) else append logLines "Déplacement vers /maps refusé par l'utilisateur."
                )
                append logLines "Toutes les maps sont valides. Étape validée automatiquement."
                step3_state = 4
                lst_log_s3.items = logLines
                if currentStep == 3 then completeStep3() else showCurrentStepUI()
                return true
            )

            if stillInvalid > 0 then (
                append logLines "--- Still missing / relative / empty ---"
                for b in bitmapList do (
                    local st = checkBitmapStatus b
                    if st == "MISSING" or st == "RELATIVE" or st == "EMPTY" then (
                        local fname = ""
                        try( fname = b.filename )catch()
                        append logLines ("  x " + filenameFromPath fname)
                    )
                )
                step3_state = 3
            ) else (
                append logLines "No missing maps, but some remain outside the project."
                step3_state = 2
                btn_main_s3.text = "MAPS OK\n⚠ CHECK PATHS"
            )
            lst_log_s3.items = logLines
            showCurrentStepUI()
            false
        )

        fn completeStep3 = ( 
            stepStates[3] = 1; updateChecklistUI()
            switchStep 4
        )

        -- ===========================================================
        -- METHODES ETAPES 4 à 9 
        -- ===========================================================
        fn hasDiffScale obj eps:0.005 = ( local s = obj.scale; (abs(s.x - s.y) > eps) or (abs(s.x - s.z) > eps) or (abs(s.y - s.z) > eps) )
        fn rPivot = (
            local diffScaleObjs = #()
            for o in objects do ( if hasDiffScale o then append diffScaleObjs o else ( CenterPivot o; WorldAlignPivot o; o.pivot = [o.center.x,o.center.y,o.min.z] ) )
            if diffScaleObjs.count > 0 do ( for o in diffScaleObjs do ( ResetXForm o; CenterPivot o; WorldAlignPivot o; o.pivot = [o.center.x, o.center.y, o.min.z] ) )
            lst_log_s4.items = #("Pivots correctement reset.")
        )
        fn rGrpPivot = ( max select none; max select all; local tempGROUP = group selection; rPivot() )

        fn wColor = (   
            local r = random 0 255; local g = random 0 255; local b = random 0 255
            local changedCount = 0
            wirecolorBackup = #()
            for o in objects do (
                if o.wirecolor == (color 0 0 0) then (
                    append wirecolorBackup #(o, o.wirecolor)
                    o.wirecolor = (color r g b)
                    changedCount += 1
                )
            )
            if changedCount > 0 then lst_log_s5.items = #("✔ Correction automatique : " + (changedCount as string) + " wirecolor(s) noir(s) remplacé(s).", "Utilisez UNDO WIRECOLOR pour restaurer uniquement les couleurs d'origine.")
            else lst_log_s5.items = #("✔ Aucun wirecolor noir trouvé.", "Aucune correction nécessaire.")
            changedCount
        )

        fn undoWirecolor = (
            local restoredCount = 0
            for item in wirecolorBackup do (
                local node = item[1]
                local originalColor = item[2]
                if isValidNode node do try(node.wirecolor = originalColor; restoredCount += 1)catch()
            )
            wirecolorBackup = #()
            btn_wire_s5.visible = false
            lst_log_s5.items = #("↩ Undo Wirecolor : " + (restoredCount as string) + " couleur(s) d'origine restaurée(s).", "Vous pouvez maintenant modifier les wirecolors manuellement ou valider l'étape.")
            restoredCount
        )

        fn listAllLayers = (
            local layerNames = #()
            for i = 0 to (LayerManager.count - 1) do append layerNames (LayerManager.getLayer i).name
            lst_log_s6.items = layerNames
        )

        fn getPrefix = (
            local n = getFilenameFile maxFileName
            n = substituteString n "_corona" ""
            n = substituteString n "_vray" ""
            n = substituteString n "-corona" ""
            n = substituteString n "-vray" ""
            return n
        )
        
        fn clearSearchReplaceState = (
            replacePending = false
            replacePreviewActive = false
            replacePendingSearch = ""
            replacePendingReplacement = ""
            replacePendingTargets = #()
            replacePreviewOriginalNames = #()
            btn_n_replace.text = "Search & Replace"
            btn_n_replace.width = 260
            btn_n_replace_cancel.visible = false
        )

        fn cancelSearchReplacePreview = (
            if replacePreviewActive do (
                undo off (
                    for item in replacePreviewOriginalNames do (
                        local obj = item[1]
                        if isValidNode obj do try(obj.name = item[2])catch()
                    )
                )
                updateNameList()
            )
            clearSearchReplaceState()
        )

        fn resetSearchReplaceConfirmation = (
            cancelSearchReplacePreview()
        )

        fn getSearchReplaceTargets = (
            local targets = #()
            -- La sélection explicite dans la liste est prioritaire, puis celle de la scène.
            if lst_names_s7.selection.isEmpty == false then (
                local selIndices = lst_names_s7.selection as array
                for i in selIndices do (
                    local obj = getNodeByName lst_names_s7.items[i]
                    if obj != undefined do appendIfUnique targets obj
                )
            ) else if selection.count > 0 then (
                for obj in selection where isValidNode obj do appendIfUnique targets obj
            ) else (
                for obj in objects where isValidNode obj do append targets obj
            )
            targets
        )

        fn updateNameList = (
            -- Réinitialisation forcée : MultiListBox peut conserver des indices sélectionnés
            -- qui désignent les anciens noms après un renommage.
            try(lst_names_s7.selection = #{})catch()
            local arr = for o in objects where isValidNode o collect o.name
            lst_names_s7.items = #()
            lst_names_s7.items = sort arr
            try(lst_names_s7.selection = #{})catch()
        )
        
        fn renameItemFromList itemName = (
            local theObj = getNodeByName itemName
            if theObj != undefined do (
                local renameDialog = dotNetObject "MaxCustomControls.RenameInstanceDialog" (theObj.name as string)
                renameDialog.Text = "Rename object"
                local dialogResult = renameDialog.Showmodal()
                if dotnet.compareenums dialogResult ((dotnetclass "System.Windows.Forms.DialogResult").OK) then (
                    local newName = renameDialog.InstanceName as string
                    if newName != "" do ( undo "Rename" on theObj.name = newName; updateNameList() )
                )
            )
        )

        fn checkPreviewImage = (
            local imgfolder = maxFilePath
            local imgbaseName = getFilenameFile maxFileName
            local imgextensions = #(".jpg", ".jpeg", ".png", ".bmp")
            local foundImage = false
            
            for ext in imgextensions where not foundImage do (
                if doesFileExist (imgfolder + imgbaseName + ext) do foundImage = true
            )
            
            if foundImage then (
                lst_log_s8.items = #("✔ Image de prévisualisation trouvée.")
                btn_prev_fix_s8.visible = false
                return true
            ) else (
                lst_log_s8.items = #("⚠ Aucune image trouvée avec le nom : " + imgbaseName)
                btn_prev_fix_s8.visible = true
                return false
            )
        )

        fn initDotNetCombobox ctrl = (
            try(
                ctrl.Items.Clear()
                ctrl.AutoCompleteMode = (dotNetClass "System.Windows.Forms.AutoCompleteMode").SuggestAppend
                ctrl.AutoCompleteSource = (dotNetClass "System.Windows.Forms.AutoCompleteSource").ListItems
                ctrl.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDown
                ctrl.BackColor = (dotNetClass "System.Drawing.Color").fromArgb 68 68 68
                ctrl.ForeColor = (dotNetClass "System.Drawing.Color").fromArgb 230 230 230
                ctrl.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
                ctrl.Text = "" 
            )catch()
        )

        fn getAiKeywords = (
            local imgfolder = maxFilePath
            local imgbaseName = getFilenameFile maxFileName
            local imgextensions = #(".jpg", ".jpeg", ".png")
            local imagePath = undefined
            for ext in imgextensions do ( if doesFileExist (imgfolder + imgbaseName + ext) do imagePath = (imgfolder + imgbaseName + ext) )
            
            -- L'étape Preview est la précondition : pas de seconde alerte redondante ici.
            if imagePath == undefined then return #()
            
            local pythonExe = "C:\\Users\\" + sysInfo.username + "\\AppData\\Local\\Microsoft\\WindowsApps\\python.exe"
            local scriptDir = "C:\\Users\\" + sysInfo.username + "\\Documents\\3ds Max 2024\\Scripts\\"
            local apiDir = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\"
            local pythonScript = scriptDir + "_MyTools_Files_MapSearch.py"
            local keywordsFile = apiDir + "MaxStack-MaxStack_FileChecker_Keywords_List.txt"
            local tempFile = getDir #temp + "\\object_list.txt"
            
            if not (doesFileExist pythonExe) then ( messageBox "Python introuvable"; return #() )
            if not (doesFileExist pythonScript) then ( messageBox ("Script AI introuvable :\n" + pythonScript) title:"AI Search"; return #() )
            if not (doesFileExist keywordsFile) then ( messageBox ("Bibliothèque de mots-clés introuvable :\n" + keywordsFile) title:"AI Search"; return #() )
            if doesFileExist tempFile then deleteFile tempFile
            
            local args = "/c \"\"" + pythonExe + "\" \"" + pythonScript + "\" \"" + imagePath + "\" \"" + tempFile + "\" \"" + keywordsFile + "\"\""
            local p = dotNetObject "System.Diagnostics.Process"
            p.StartInfo.FileName = "cmd.exe"; p.StartInfo.Arguments = args; p.StartInfo.WindowStyle = (dotNetClass "System.Diagnostics.ProcessWindowStyle").Hidden; p.StartInfo.UseShellExecute = false; p.StartInfo.CreateNoWindow = true
            p.Start(); p.WaitForExit()
            
            local keywordsFound = #()
            if doesFileExist tempFile then (
                local f = openFile tempFile
                local outputLines = #()
                while not eof f do append outputLines (readLine f)
                close f
                if outputLines.count > 0 and outputLines[1] == "__AI_SEARCH_ERROR__" then (
                    local errorText = ""
                    for i = 2 to outputLines.count do errorText += outputLines[i] + "\n"
                    messageBox errorText title:"AI Search — modèles indisponibles"
                    return #()
                )
                for line in outputLines do (
                    local cleanLine = trimLeft (trimRight line)
                    if cleanLine != "" do append keywordsFound cleanLine
                )
                return keywordsFound
            ) else (
                messageBox "AI Search n'a créé aucun résultat." title:"AI Search"
                return #()
            )
        )

        fn initStep9Keywords = (
            local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
            local allCBX = #(cbx_cat, cbx_subcat)
            join allCBX kFields
            
            for c in allCBX do initDotNetCombobox c
            
            -- Categories
            local catNames = #()
            for d in database do append catNames d.catName
            sort catNames
            fillComboBox cbx_cat catNames

            -- Keywords Cache depuis le Splash Screen
            if netKeywords_Cache != undefined do (
                for kf in kFields do (
                    kf.BeginUpdate()
                    kf.Items.AddRange netKeywords_Cache
                    kf.EndUpdate()
                )
            )

            -- Auto-remplissage via le fichier OK ou les dossiers
            if maxFileName != "" do (
                local txt_filename = (maxFilePath+maxFileName+"_CHECKED_OK.txt")
                local fileExists = doesFileExist txt_filename
                local loaded_cat = ""; local loaded_subcat = ""; local loaded_keywords = #()
                
                if fileExists then (
                    local f = openFile txt_filename
                    while not eof f do (
                        local line = trimLeft (trimRight (readLine f))
                        if line != "" do (
                            if (matchPattern line pattern:"--*") then loaded_subcat = substring line 3 -1
                            else if (matchPattern line pattern:"-*") then loaded_cat = substring line 2 -1
                            else if line != (sysInfo.username as string) then append loaded_keywords line
                        )
                    )
                    close f
                    
                    if loaded_cat != "" do ( 
                        cbx_cat.Text = loaded_cat
                        local foundSubs = #()
                        for d in database do (
                            if (stricmp d.catName loaded_cat) == 0 do (
                                for s in d.subcats do append foundSubs s; sort foundSubs; exit
                            )
                        )
                        fillComboBox cbx_subcat foundSubs
                    )
                    if loaded_subcat != "" do cbx_subcat.Text = loaded_subcat
                    local idx = 1
                    for k in loaded_keywords do ( if idx <= 15 do ( kFields[idx].Text = k; idx += 1 ) )
                ) else (
                    local searchPathFolders = filterString maxFilePath "\\"
					if searchPathFolders.count >= 3 do (
						local folderCat = resolveFolderAlias searchPathFolders[3]
                        for d in database do ( if (d.catName == folderCat) or ((d.catName + "s") == folderCat) do ( 
                            cbx_cat.Text = d.catName; 
                            local subs = #()
                            for s in d.subcats do append subs s
                            sort subs
                            fillComboBox cbx_subcat subs
                            exit 
                        ) )
                    )
                    if searchPathFolders.count >= 4 do (
						local folderSub = resolveFolderAlias searchPathFolders[4]
						local currentSubs = #()
						if cbx_cat.Text != "" then (
							for d in database do (
								if (stricmp d.catName cbx_cat.Text == 0) do (
									for s in d.subcats do append currentSubs s
								)
							)
						) else (
							for d in database do join currentSubs d.subcats
						)
						if currentSubs != undefined and currentSubs.count > 0 do (
							for s in currentSubs do (
								if (stricmp folderSub s == 0) or (stricmp folderSub (s+"s") == 0) or (matchPattern folderSub pattern:(s+"*") ignoreCase:true) do (
									cbx_subcat.Text = s; exit
								)
							)
						)
					)
                    if searchPathFolders.count >= 3 and (stricmp searchPathFolders[3] "BRANDS" == 0) do ( for f in kFields do ( if f.Text == "" do ( f.Text = "Brands"; exit ) ) )
                    if searchPathFolders.count >= 3 and (stricmp searchPathFolders[3] "dimensiva" == 0) do ( for f in kFields do ( if f.Text == "" do ( f.Text = "Dimensiva"; exit ) ) )
                )
            )
        )

        -- ===========================================================
        -- CASCADE D'AUTO-CHECK (La magie du passage automatique)
        -- ===========================================================
        fn switchStep newStep =
        (
            local isMovingForward = (newStep > currentStep)
            
            if isMovingForward then (
                local autoChecking = true
                while autoChecking do (
                    autoChecking = false
                    
                    if newStep == 3 and stepStates[3] == 0 then (
                        local mapsOk = doStep3_Scan()
                        if mapsOk then ( stepStates[3] = 1; newStep = 4; autoChecking = true )
                    )
                    if newStep == 5 and stepStates[5] == 0 then (
                        -- Correction immédiate puis passage automatique à l'étape suivante.
                        -- Le bouton Undo reste disponible dans l'étape suivante tant qu'une restauration est possible.
                        local changedCount = 0
                        undo "Auto-fix black wirecolor" on changedCount = wColor()
                        wirecolorAutoProcessed = true
                        stepStates[5] = 1
                        newStep = 6
                        autoChecking = true
                    )
                    if newStep == 6 and stepStates[6] == 0 then (
                        if LayerManager.count <= 1 then ( stepStates[6] = 1; newStep = 7; autoChecking = true )
                    )
                    if newStep == 8 and stepStates[8] == 0 then (
                        local hasImg = checkPreviewImage()
                        if hasImg then ( stepStates[8] = 1; newStep = 9; autoChecking = true )
                    )
                )
            )

            currentStep = newStep
            updateChecklistUI()
            showCurrentStepUI()
            
            if currentStep == 1 and stepStates[1] == 0 do (
                lst_log_s1.items = #("Cliquez sur le bouton pour analyser la scène et exécuter le nettoyage automatique (Clean Reset).")
            )
            if currentStep == 2 and stepStates[2] == 0 do doCheckFilename()
            if currentStep == 3 and stepStates[3] == 0 do doStep3_Scan()
            if currentStep == 4 do lst_log_s4.items = #("⚠ ATTENTION :","Vérifier manuellement certains pivots comme les luminaires (pivot = plafond) et cadres (pivot = centre dos / mur).","\n","Cliquez sur l'action à effectuer.")
            if currentStep == 6 do (
                if stepStates[6] == 1 then lst_log_s6.items = #("✔ Seul le layer 0 est présent.", "Étape auto-validée.")
                else listAllLayers()
            )
            if currentStep == 7 do ( edt_n_pref.text = getPrefix(); updateNameList() )
            if currentStep == 8 do checkPreviewImage()
        )

        -- ===========================================================
        -- INITIALISATION ET EVENTS DE NAVIGATION MAIN
        -- ===========================================================
        on rlMasterChecker open do ( 
            -- ON MASQUE TOUT IMMÉDIATEMENT POUR ÉVITER LES OVERLAPS UI
            hideAllUI()
            
            -- ON INITIALISE TOUS LES DOTNET ICI POUR ASSURER LA CRÉATION DU HANDLE
            initStep9Keywords() 
            
            edt_before_s2.text = ""
            edt_after_s2.text  = ""
            
            lbl_reload.visible = false
            switchStep 1 
        )

        on rlMasterChecker close do ( if replacePreviewActive do cancelSearchReplacePreview() )

        on btn_next pressed do ( 
            if currentStep == 7 and replacePreviewActive do cancelSearchReplacePreview()
            if currentStep < 9 do switchStep (currentStep + 1) 
        )
        on btn_prev pressed do ( 
            if currentStep == 7 and replacePreviewActive do cancelSearchReplacePreview()
            if currentStep > 1 do switchStep (currentStep - 1) 
        )

        -- EVENTS S1 (CORONA & RESET)
        on btn_main_s1 pressed do ( doCheckCorona() )
        on btn_recheck_s1 pressed do ( doCheckCorona() )
        
        on btn_converter_s1 pressed do (
            try ( actionMan.executeAction 572340868 "7" ) catch ( messageBox "Impossible d'ouvrir le Corona Converter.\nVérifiez que Corona est bien installé." title:"Erreur MaxStack" )
        )
        
        on btn_done_s1 pressed do (
            local currRend = classOf renderers.current as string
            local isCorona = matchPattern currRend pattern:"*Corona*" ignoreCase:true
            if not isCorona then (
                local warningLines = lst_log_s1.items
                append warningLines "---"
                append warningLines "⚠ Validé manuellement sans conversion au moteur Corona."
                lst_log_s1.items = warningLines
                completeStep1()
            ) else (
                lst_log_s1.items = #("✔ Matériaux nettoyés et moteur validé.", "Lancement du Clean Reset...")
                doCleanReset()
            )
        )

        -- EVENTS S2 (FILENAME)
        on btn_main_s2 pressed do ( if currentStep == 2 and step2_state == 1 do doCheckFilename() )
        
        on btn_confirm_s2 pressed do (
            if currentStep == 2 and step2_state == 2 then (
                local fullPath = maxFilePath + maxFileName
                local finalName = trimLeft (trimRight edt_after_s2.text)
                local result   = doRenameOnDisk fullPath finalName

                if result[1] == true then (
                    if result[2] == "unchanged" then lst_log_s2.items = #("File was already correctly named.", "Nothing changed.")
                    else (
                        local newFull = result[2]
                        local reloaded = loadMaxFile newFull useFileUnits:true quiet:true
                        if reloaded then lst_log_s2.items = #("✔  File renamed successfully.", "", "New name : " + (getFilenameFile newFull) + ".max", "Path     : " + (getFilenamePath newFull), "", "File reloaded in 3ds Max.")
                        else lst_log_s2.items = #("✔  File renamed on disk.", "⚠  Could not auto-reload — please reopen manually:", newFull)
                    )
                    completeStep2()
                ) else lst_log_s2.items = #("ERROR renaming file :", result[2])
            )
        )

        -- EVENTS S3 (MAPS)
        on btn_main_s3 pressed do (
            if step3_state == 1 then doStep3_Scan()
            else if step3_state == 2 then doStep3_Relink()
        )
        on btn_force_s3 pressed do ( ATSOps.visible = true; atsops.refresh() )
        on btn_copy_local_s3 pressed do ( undo "Copy Maps To Local" on copyOutsideMapsToLocal() )
        
        on btn_remove_missing_s3 pressed do (
            undo "Remove Missing Maps" on (
                collectAllBitmaps()
                local count = 0
                for b in bitmapList do (
                    if (checkBitmapStatus b) == "MISSING" or (checkBitmapStatus b) == "RELATIVE" do (
                        try( b.filename = ""; count += 1 )catch()
                    )
                )
                messageBox ((count as string) + " bitmaps missing effacés de la scène.") title:"Remove Missing"
                doStep3_Scan()
            )
        )
        
        on btn_recheck_s3 pressed do ( doStep3_Scan() )
        
        on btn_done_s3 pressed do ( completeStep3() )

        -- EVENTS S4 (PIVOTS)
        on btn_piv_each_s4 pressed do ( undo "Pivot Each" on rPivot() )
        on btn_piv_grp_s4 pressed do ( undo "Pivot Group" on rGrpPivot() )
        on btn_done_s4 pressed do ( stepStates[4] = 1; updateChecklistUI(); switchStep 5 )

        -- EVENTS S5 (WIRECOLOR)
        on btn_wire_s5 pressed do ( undo "Restore Wirecolor" on undoWirecolor() )
        on btn_done_s5 pressed do ( stepStates[5] = 1; updateChecklistUI(); switchStep 6 )

        -- EVENTS S6 (LAYERS)
        on btn_lay_fix_s6 pressed do (
            undo "Fix Layers" on (
                local layer0 = layermanager.getLayerFromName "0"
                for o in objects do if o.layer.name != "0" do layer0.addNode o
                local i = LayerManager.count - 1
                while (i > 0) do (
                    local lyr = LayerManager.getLayer i
                    if (lyr.name != "0" and lyr.getNumChildren() == 0) do LayerManager.deleteLayerByName (lyr.name as string)
                    i -= 1
                )
                listAllLayers()
            )
        )
        on btn_done_s6 pressed do ( stepStates[6] = 1; updateChecklistUI(); switchStep 7 )

        -- EVENTS S7 (NAMES)
        on btn_n_all pressed do (
            if replacePreviewActive do cancelSearchReplacePreview()
            local pfx = edt_n_pref.text; local base = edt_n_base.text
            undo "Name All" on ( for o in objects do ( if base != "" then o.name = pfx + "_" + base else if (findString o.name pfx) == undefined do o.name = pfx + "_" + o.name ) )
            updateNameList()
        )
        
        on btn_n_sel pressed do (
            if replacePreviewActive do cancelSearchReplacePreview()
            local pfx = edt_n_pref.text; local base = edt_n_base.text
            local targetObjs = #()
            
            if lst_names_s7.selection.isEmpty == false then (
                local selIndices = lst_names_s7.selection as array
                for i in selIndices do (
                    local obj = getNodeByName lst_names_s7.items[i]
                    if obj != undefined do append targetObjs obj
                )
            ) else (
                targetObjs = selection as array
            )
            
            if targetObjs.count > 0 do (
                undo "Name Selected" on (
                    for o in targetObjs do (
                        if base != "" then o.name = pfx + "_" + base 
                        else if (findString o.name pfx) == undefined do o.name = pfx + "_" + o.name 
                    )
                )
                updateNameList()
            )
        )
        
        on btn_n_grp pressed do (
            if replacePreviewActive do cancelSearchReplacePreview()
            local pfx = edt_n_pref.text; local Selmain = #()
            for o in objects do ( if o.parent == undefined do append Selmain o )
            undo "Name Group" on ( if Selmain.count >= 2 then ( for s in Selmain do s.name = pfx + "_" + s.name ) else ( for s in Selmain do s.name = pfx ) )
            updateNameList()
        )
        
        on edt_n_search changed txt do resetSearchReplaceConfirmation()
        on edt_n_repl changed txt do resetSearchReplaceConfirmation()

        on btn_n_replace pressed do (
            local sText = edt_n_search.text
            local rText = edt_n_repl.text
            if sText == "" then (
                resetSearchReplaceConfirmation()
            ) else if not replacePending or replacePendingSearch != sText or replacePendingReplacement != rText then (
                -- Premier clic : aperçu temporaire, jamais une validation définitive.
                cancelSearchReplacePreview()
                replacePendingTargets = getSearchReplaceTargets()
                replacePendingSearch = sText
                replacePendingReplacement = rText
                replacePreviewOriginalNames = #()
                undo off (
                    for o in replacePendingTargets where isValidNode o do (
                        if matchPattern o.name pattern:("*" + replacePendingSearch + "*") do (
                            append replacePreviewOriginalNames #(o, o.name)
                            o.name = substituteString o.name replacePendingSearch replacePendingReplacement
                        )
                    )
                )
                replacePending = true
                replacePreviewActive = true
                btn_n_replace.text = "APPLY"
                btn_n_replace.width = 125
                btn_n_replace_cancel.visible = true
                updateNameList()
            ) else (
                -- Second clic : on annule l'aperçu, puis on réapplique dans un Undo définitif.
                local finalTargets = replacePendingTargets
                local finalSearch = replacePendingSearch
                local finalReplacement = replacePendingReplacement
                cancelSearchReplacePreview()
                undo "Search Replace" on (
                    for o in finalTargets where isValidNode o do (
                        if matchPattern o.name pattern:("*" + finalSearch + "*") do o.name = substituteString o.name finalSearch finalReplacement
                    )
                )
                updateNameList()
            )
        )
        
        on btn_n_replace_cancel pressed do cancelSearchReplacePreview()

        on lst_names_s7 doubleClicked idx do (
            if replacePreviewActive do cancelSearchReplacePreview()
            if idx > 0 do renameItemFromList lst_names_s7.items[idx]
        )
        on btn_done_s7 pressed do (
            if replacePreviewActive do cancelSearchReplacePreview()
            stepStates[7] = 1
            updateChecklistUI()
            switchStep 8
        )

        -- EVENTS S8 (PREVIEW)
        on btn_prev_fix_s8 pressed do (
            local imgfolder = maxFilePath
            local checkFiles = #()
            
            for ext in #(".jpg", ".jpeg", ".png", ".bmp") do (
                join checkFiles (getFiles (imgfolder + "*" + ext))
            )
            
            if checkFiles.count == 0 then (
                messageBox "Aucune image trouvée dans ce dossier." title:"Preview image"
            ) else (
                createDialog rl_selectImage
            )
        )
        on btn_done_s8 pressed do ( stepStates[8] = 1; updateChecklistUI(); switchStep 9 )

        -- EVENTS S9 (KEYWORDS)
        on cbx_cat SelectedIndexChanged s e do (
            local subs = #()
            for d in database do (
                if (stricmp d.catName s.Text) == 0 do (
                    for c in d.subcats do append subs c
                    sort subs
                    exit
                )
            )
            fillComboBox cbx_subcat subs
        )
        
        on btn_ai_s9 pressed do (
            local aiResults = getAiKeywords()
            if aiResults.count > 0 do (
                local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
                local idx = 1
                for f in kFields do ( if f.Text == "" and idx <= aiResults.count do ( f.Text = aiResults[idx]; idx += 1 ) )
            )
        )
        
        fn doSaveOkFile silent:false = (
			if cbx_cat.Text == "" then (
				messageBox "⚠ Please select a Category before saving." title:"Save OK File"
				return false
			)
			if cbx_subcat.Text == "" then (
				messageBox "⚠ Please select a Subcategory before saving." title:"Save OK File"
				return false
			)
			
			local txt_filename = (maxFilePath+maxFileName+"_CHECKED_OK.txt")
			local txt_file = createfile txt_filename
			format ("-"+(cbx_cat.Text)+"\n") to:txt_file
			format ("--"+(cbx_subcat.Text)+"\n") to:txt_file
			local kFields = #(cbx_k1, cbx_k2, cbx_k3, cbx_k4, cbx_k5, cbx_k6, cbx_k7, cbx_k8, cbx_k9, cbx_k10, cbx_k11, cbx_k12, cbx_k13, cbx_k14, cbx_k15)
			for f in kFields do ( if f.Text != "" do format (f.Text + "\n") to:txt_file )
			format (sysInfo.username as string) to:txt_file
			close txt_file
			stepStates[9] = 1; updateChecklistUI()
			if not silent do messageBox "OK File Generated!" title:"Done"
			return true
		)

		on btn_done_s9 pressed do ( doSaveOkFile silent:false )
        
		fn jsonEscapeString s = (
			local r = s as string
			r = substituteString r "\\" "\\\\"
			r = substituteString r "\"" "\\\""
			return r
		)

		fn notifyLibraryAddAsset txtPath = (
			try (
				local http = dotNetObject "System.Net.WebClient"
				http.Headers.Add "Content-Type" "application/json"
				http.Headers.Add "User-Agent" "MaxScript"
				local body = "{\"token\":\"RENDER_TEAM_2024\",\"txt_path\":\"" + (jsonEscapeString txtPath) + "\"}"
				local response = http.UploadString "http://10.13.54.151:8000/library/add-asset" "POST" body
				format "Iconia Library add-asset launched: %\n" response
				return true
			) catch (
				format "Iconia Library add-asset failed for % : %\n" txtPath (getCurrentException())
				return false
			)
		)

        on btn_final_validate_s9 pressed do (
			-- Sauvegarde du OK file (avec validation cat/subcat intégrée)
			local saved = doSaveOkFile silent:true
			if not saved do return false
			
			-- Sauvegarde automatique de la scène max
			if maxFilePath != "" do saveMaxFile (maxFilePath + maxFileName) quiet:true
			
			-- Validation de la présence de l'image
			local imgfolder = maxFilePath
			local imgbaseName = getFilenameFile maxFileName
			local imgextensions = #(".jpg", ".jpeg", ".png", ".bmp")
			local hasImg = false
			for ext in imgextensions where not hasImg do ( if doesFileExist (imgfolder + imgbaseName + ext) do hasImg = true )
			
			if not hasImg then (
				messageBox "⚠ Validation finale impossible !\n\nL'image de preview est introuvable.\nVeuillez vérifier qu'elle est bien présente." title:"Validation Finale"
			) else (
				-- Ajout rapide dans la bibliothèque SQLite + régénération HTML sans scan complet
				local txt_filename = (maxFilePath+maxFileName+"_CHECKED_OK.txt")
				notifyLibraryAddAsset txt_filename
				
				local res = yesNoCancelBox "Le fichier a été enregistré et vérifié avec succès !\n\nVoulez-vous fermer 3ds Max ?\n\nOui = Fermer 3ds Max\nNon = Laisser ouvert" title:"Validation Finale"
				if res == #yes then (
					quitMax #noPrompt
				) else (
					-- LOAD FOLDER ALIASES CSV
					local aliasCsvPath = "L:\\0-Documentation\\3DS Max Configuration\\3DS Max Plugins\\Antoine\\API\\MaxStack-MaxStack_FileChecker_FolderAliases.csv"
					local folderAliases = #()  -- array de paires #(rawFolder, resolvedName)
					if doesFileExist aliasCsvPath do (
						local fAlias = openFile aliasCsvPath
						while not eof fAlias do (
							local parts = filterString (readLine fAlias) ";"
							if parts.count >= 2 do (
								local raw      = trimLeft (trimRight parts[1])
								local resolved = trimLeft (trimRight parts[2])
								if raw != "" and resolved != "" do append folderAliases #(raw, resolved)
							)
						)
						close fAlias
					)

					-- Ferme le Splash et ouvre la fenêtre principale
					try(DestroyDialog rlMasterChecker) catch()
				)
			)
		)
    )

    -- Le script démarre par l'ouverture du Splash Screen qui, une fois fini, ouvrira rlMasterChecker
    rl_Splash()
)
