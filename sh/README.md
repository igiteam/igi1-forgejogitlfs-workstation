# sh

This is a github repo on https://github.com/igiteam/sh

THIS ESSENTALLY TWO APPS IN ONE FOLDER STRUCTURE:

SH -> igiteam.github.io/sh
bash script viewer

---

SHBash -> shbash.netlify.app
List of SH (bash) scripts stored on digitalocean/spaces/rtx/filename.sh

---

sh/
public/index.html -> netlify https://shbash.netlify.app
index.html -> github https://igiteam.github.io/sh
when netlify-deploy.sh runs, it updates both websites on their URLs in the same time
(I wrote this down, because it was a bit confusing how it works)
https://igiteam.github.io/sh is stored on github pages as a static website
index.html

![This is how you host a static index.html website on Github.com](https://raw.githubusercontent.com/igiteam/sh/main/Pages.png "This is how you host a static index.html website on Github.com")

if website changes. I must update .env
DO*CDN_ENDPOINT=https://cdn.gitgpt.chat
and in netlify as well where the \_function_app* is
you need to login to Netlify
https://app.netlify.com/projects/shbash/configuration/env#environment-variables
but actually I realised I don't need .env on netlify. But just fyi, if a netlify website(react-app) needs .env variables stored safely this is where you do it.

So the reason why I don't need .env on netlify,
because: when I run netlify_deploy.sh
->it runs python3 spaces_files.py
it creates the list of uploaded sh(bash) scripts stored on
[[[digitalocean/spaces/rtx]]]
and updates public/index.html -> netlify https://shbash.netlify.app
and also updates the repo on https://github.com/igiteam/sh
When the repo (https://github.com/igiteam/sh) is updated it updates the github pages as well on:
https://igiteam.github.io/sh

# Why this exists?

sh(bash) scripts by default cannot be previewed because digitalocean direct link will trigger yourfilename.sh to be downloaded on disk.
On my mac it downloadd to Downloads/yourfilename.sh

When I stumbled across github raw(raw script files) and htmlpreview.github.io(allow html files to be viewed(by default using github.raw.yourfile.html) this allows to actually view as a html document. unfortunatelly how cloud providers allowing free static site hostage changed. for example before on Google Drive you were able to store static html files, now it only shows raw file instead to display the website)

Anyway bascally this two idea merged, that you can store the .sh files on digital ocean for cheap, but how to display them easily, or github raw sh files as well.

So this does two:
Display the sh files, and allows users to install them easily on ubuntu/unix systems.
I used it developing WineJs, and AppGenesys.
Than I realised how would be the easiest way to share installation scripts.
And when I started to use AI to write these templates it evolved into this
bigger project.

I think it's pretty cool.

Here you can add the sh code as an iframe

<!-- Default: Just code + line numbers, no buttons -->
<iframe src="https://igiteam.github.io/sh?url=https://cdn.gitgpt.chat/rtx/urlpixelprint.sh"
        style="width: 100%; height: 500px;" title="embed iframe"></iframe>

<!-- With hidden download button (appears when &download=1) -->
<iframe src="https://igiteam.github.io/sh?url=https://cdn.gitgpt.chat/rtx/urlpixelprint.sh&download=1"
        style="width: 100%; height: 500px;" title="embed iframe"></iframe>
