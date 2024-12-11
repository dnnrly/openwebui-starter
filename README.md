# Open WebUI - Starter

This repository is a starting point for your Open WebUI project. It has a few basic resources to get you started and tells you how to run a simple service.

It is all based around [Open WebUI](https://docs.openwebui.com/). This was selected as it has most of the components and features that you need to experiment with models and interact with them.

> If you are participating in a hackathon, I would recommend that you run through the instructions to run the service locally and then pull some of the models. This will allow you to start your hackathon activities straight away.

## Downloading and running Open WebUI

First, clone this project and from the root of the project, run:

```shell
docker-compose up open-webui
```

This may take some time to download and run so grab a cup of tea and maybe some toast. I'll see you in a few minutes.

When the service is running, you can access the Open WebUI UI at http://localhost:8080. Auth has been disabled in this local version so you can just jump straight in.

## Downloading models

Before you can chat to your AI, you need to download some models. We'll go through downloading `llama3.2` to show you how before discussion the details.

### Downloading `llama3.2`

1. Click on the user icon in the top right of the Open WebUI UI
2. Click on `Admin Panel` frome the drop down menu
3. Click on `Settings` tab on the top left of the page
4. Click on `Connections` to reveal to review the different external resources that are configured
5. Click on the spanner icon next to the `Ollama` URL
6. In the `Model` field, enter `llama3.2:3b` then click on the download icon (an arrow pointing down into a tray)

Next, you'll have to do some more waiting so grab another cup of tea.

### Chatting with your model

You can now chat with your model. When you open a new chat, you'll see a drop down in the top left of the conversation page. Select `llama3.2` from the drop down and start chatting. You'll see the model respond to your messages.


# Using RAG with your chat

If you would like to get your AI to give answers specific to a body of knowledge, you can do this using a technique called RAG (Retrtieval Augmented Generation). This allows you to embed existing documentation and context into your prompt so that it can be included in the answer that is generated.

## Using RAG with Open WebUI

<TODO>

## Interesting source data

Here are some interesting sources of data that can be used in your RAG implementation that would be suitable for experimenting with:
* https://handbook.gitlab.com/
* https://github.com/18F/handbook/tree/main/pages
* https://github.com/sourcegraph/handbook

These have been sourced from https://github.com/hkdobrev/awesome-handbooks which has many examples of documentation that are suitable for this kind of knowledge retrieval.


## Running Ollama Natively to make use of GPU (Written with MacOS in mind, but might work just as easily with Windows or Linux too, I've just not tested it)

If you're running on a MacOS system, such as a newer MacBook Pro with an Apple Silicon chip (M1, M2, M3 or even the new M4), then running Ollama natively on your laptop will likely yield much better performance than through Docker. 

This is a seperate way to run the whole stack, so you don't need to follow the steps above, and just follow these steps on their own.

1. Install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/
2. Install Ollama from https://ollama.com/download/mac
3. Follow install instructions for Ollama in your terminal until asked to run `ollama run ...`, at that point instead run `ollama run llama3.1:8b`. If you have a laptop with less than 16GB of RAM you might want to run `ollama run llama3.2:3b` instead, and if that gives you issues, then try `ollama run llama3.2:1b`.
4. Once that is running, you should be able to chat with the AI model in your terminal, and it should be fairly responsive! After that all works though, say bye by running `/bye` in the chat.
5. Now that works, we are going to install OpenWebUI, to do that, all you need to do is make sure you're at the root of this repo and run `docker compose -f ./docker-compose-native-ollama.yaml up`
6. That should download some stuff and spin everything up for you, once that's done and you see it say something like, `openwebui is running at 127.0.0.1:8080`, cmd + click on that or go to localhost:8080 in your browser and you should be good to go!

