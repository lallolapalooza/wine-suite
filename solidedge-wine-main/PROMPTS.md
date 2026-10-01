# The prompts this work was done from

Reproduced verbatim. Nothing else from any vendor's material is included here — the repository
contains no Siemens, Autodesk or Microsoft files, only patches, tooling and measurements.

---

## 1

> use /home/asdf/Downloads/Solid_Edge_X_Web_Installer_2026 (1).exe the goa lis to make it run in
> wine and fix the following When trying to sketch the 3D viewport flickers black continuously,
> making it unusable
> Can't close the sketch. When clicking the close sketch button it shows 06cc:fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented in the terminal
> Can't close Solid Edge itself, the x icon/button in the top right is even greyed out
>  you can use the experience in /home/asdf/projects/powerbi-linux and /home/asdf/projects/autocad2027-private-main to make it work. i recommend yo uclone the wine source and aplly the patches from both sources first, then try to run wine. you will need to disassemble solid edge to find out what is wrong and also use the wine logs. you will need to match up actions to logs and logs to dissasembled solid edge code to create the wine pathces. use a vnc server display to autonomously see the app and interact with it. ther eis a windows vm machine you can use as reference for solid edge behavior on wine and you cam compare win32 calls between windows and wine. run autonomously in a loop until the goal is achieved, you cna use subagents to parallelize tasks for speed and context management. store state to resist compacion as this process cna take many hours, as many as 120 hours.

## 2

> also avoid oom by checking meory ussage before running compilation for example or running the app

## 3

> the patches from both sources, if used, should be included in the working directory.

## 4

> for wine compilatoin isntructoins use https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine

## 5 (the fullest statement of the brief; left by the user as a file in this directory)

> Can't close the sketch. When clicking the close sketch button it shows 06cc:fixme:dwmapi:DwmGetWindowAttribute attribute 14 not implemented in the terminal
>    Can't close Solid Edge itself, the x icon/button in the top right is even greyed out
>    you can use the experience in /home/asdf/projects/powerbi-linux and /home/asdf/projects/autocad2027-private-main to make it work. i recommend yo uclone the wine source and aplly the patches from both sources first, then try to
>    run wine. you will need to disassemble solid edge to find out what is wrong and also use the wine logs. you will need to match up actions to logs and logs to dissasembled solid edge code to create the wine pathces. use a vnc
>    server display to autonomously see the app and interact with it. ther eis a windows vm machine you can use as reference for solid edge behavior on wine and you cam compare win32 calls between windows and wine. run autonomously
>    in a loop until the goal is achieved, you cna use subagents to parallelize tasks for speed and context management. store state to resist compacion as this process cna take many hours, as many as 120 hours.
>    also avoid oom by checking meory ussage before running compilation for example or running the app
>    use disk backed temp folders.
>    you will work with other agents now who mgiht use ram and disk. you can stop if you don't have enough disk space
>    the patches from both sources, if used, should be included in the working directory.
>    for wine compilation insturctions use https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine. use all wine best practices, except LLM use, which means we will not submit this work to wine.
>    if the app uses the net framework before versoin 6, you will need to deompile the net sdk and the app, to trace the app through the sdk into a win32 call that needs to be fixed in wine, which will probably show up as an error in the wine logs.
>    you can make a diff between the wine logs and the win32 api logs under windows. pick options based on reward not cost.
>
>
>    look at all user messges in the prompts and publish the prompts but not the whole folder because they contain proprietary material belonging to several companies

*(the file this was copied from has been left in place as `Can t close the sketch.txt`)*
