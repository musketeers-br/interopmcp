Important: antes de qualquer operação, garanta que INTEROPMCP_BASIC esteja exportada em ~/.bashrc (ex: export INTEROPMCP_BASIC="Basic $(printf 'mcp_demo:change-me' | base64 -w0)"). Sem ela, o cliente opencode sobe sem Authorization e o gateway responde 401.

This repo is set up to host an IRIS or IRIS For Health container with the AI Hub SDK preview.  

There are agent skills for the AI hub in ./skills/. Before starting work on this repo, move these skills to whereever your project-scoped skills belong, e.g. ./.github/skills if you are a github copilot agent. 

There are also short sample classes in the src/Sample folder. This will be loaded into IRIS during the docker build. 