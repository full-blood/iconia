/*
================================================================================
Script Name: Iconia_ScriptHelper
Category: Iconia
Description: Aide pour les scripts Iconia. 
             Affiche une description si disponible pour chaque script.
================================================================================
*/

macroScript Iconia_ScriptManager
    category:"Iconia" 
    tooltip:"Iconia Scripts description"
    buttonText:"Iconia tools Help"
(
    rollout Iconia_Manager_UI "Iconia Script Helper" width:450 height:320
    (
        -- Stockage : #( #(NomBouton, Description), ... )
        local scriptsData = #()
        
        dropdownlist ddl_scripts "Scripts Iconia disponibles :"
        label lbl_desc "" height:200 align:#left
        
        fn loadScripts = (
            scriptsData = #() 
            local macroFiles = getFiles (getDir #userMacros + "\\*Iconia*.mcr")
            
            for file in macroFiles do (
                local f = openFile file
                local headerStr = ""
                local bText = (filenameFromPath file) -- Nom par d faut si buttonText non trouv 
                local isDescription = false
                
                if f != undefined do (
                    while not eof f do (
                        local l = readLine f
                        local cleanLine = trimLeft (trimRight l)
                        
                        -- 1. Recherche du buttonText (ce qui sera affich  dans la liste)
                        if matchPattern cleanLine pattern:"*buttonText:*" then (
                            local tokens = filterString l "\"" -- On d coupe par les guillemets
                            if tokens.count >= 2 do bText = tokens[2]
                        )
                        
                        -- 2. Recherche du d but de la description
                        if matchPattern cleanLine pattern:"Description:*" ignoreCase:true then (
                            isDescription = true
                            local textAfter = substring cleanLine 13 -1
                            headerStr += (trimLeft textAfter) + "\r\n"
                        )
                        -- 3. Capture des lignes suivantes de la description
                        else if isDescription and cleanLine != "*/" and not matchPattern cleanLine pattern:"*====*" then (
                            -- Si on tombe sur macroScript, on a fini la description
                            if matchPattern cleanLine pattern:"*macroScript*" then (
                                isDescription = false
                            ) else (
                                headerStr += cleanLine + "\r\n"
                            )
                        )
                    )
                    close f
                )
                
                -- V rification si une description a  t  trouv e
                if trimLeft (trimRight headerStr) == "" do (
                    headerStr = "pas encore de description"
                )
                
                append scriptsData #(bText, headerStr)
            )
            
            -- Tri alphab tique de la liste par le nom du bouton
            fn compareNames v1 v2 = (
                if v1[1] < v2[1] then -1 else if v1[1] > v2[1] then 1 else 0
            )
            qsort scriptsData compareNames
            
            -- Mise   jour de la liste d roulante
            local nameList = for s in scriptsData collect s[1]
            ddl_scripts.items = nameList
        )
        
        -- Initialisation au lancement
        on Iconia_Manager_UI open do (
            loadScripts()
            if scriptsData.count > 0 do (
                lbl_desc.text = scriptsData[1][2]
            )
        )
        
        -- Changement de script dans la liste
        on ddl_scripts selected idx do (
            lbl_desc.text = scriptsData[idx][2]
        )
    )
    
    createdialog Iconia_Manager_UI
)