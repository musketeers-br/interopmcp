ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2027.1.0AI.109.0
FROM $IMAGE

WORKDIR /home/irisowner

ARG NAMESPACE="IRISAPP"

ENV IRISUSERNAME "_SYSTEM"
ENV IRISPASSWORD "SYS"
ENV IRISNAMESPACE $NAMESPACE
ENV PYTHON_PATH=/usr/irissys/bin/:/usr/irissys/mgr/python
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

COPY requirements.txt /home/irisowner/dev/requirements.txt
COPY merge.cpf /home/irisowner/dev/merge.cpf
COPY iris.script /home/irisowner/dev/iris.script
COPY --chown=51773:51773 iris-main.log /home/irisowner/iris-main.log
ENV PYTHONPATH="/usr/irissys/lib/python"
ENV PATH "/usr/irissys/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/irisowner/bin"

RUN  python3 -m venv "/home/irisowner/.venvs/mcp-tools" && \
    "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install -r /home/irisowner/dev/requirements.txt --break-system-packages --target /usr/irissys/mgr/python && \
    "/home/irisowner/.venvs/mcp-tools/bin/python" -m pip install typing-extensions --upgrade --break-system-packages --target /usr/irissys/mgr/python

COPY src /home/irisowner/dev/src
COPY module.xml /home/irisowner/dev/module.xml

# Instala o módulo de extração de PDF no Python embutido. O COPY src cria
# arquivos root:root e o RUN roda como irisowner; usa root só para instalar e
# remover o módulo da cópia do src (o zpm load não deve vê-lo como ObjectScript).
USER root
RUN cp /home/irisowner/dev/src/br/musketeers/InteropMCP/Demo/python/interopmcp_pdf.py \
        /usr/irissys/mgr/python/interopmcp_pdf.py && \
    chown 51773:51773 /usr/irissys/mgr/python/interopmcp_pdf.py && \
    rm -f /home/irisowner/dev/src/br/musketeers/InteropMCP/Demo/python/interopmcp_pdf.py
USER 51773

RUN iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
    iris session IRIS < /home/irisowner/dev/iris.script && \
    iris stop IRIS quietly

# O agente pode levar mais de 60s em um PDF com as políticas no prompt. O
# timeout padrão do módulo CSP (Server_Response_Timeout=60) devolve 504 antes
# de a resposta chegar ao cliente; eleva o limite para 300s.
RUN sed -i 's/^Server_Response_Timeout=.*/Server_Response_Timeout=300/' \
        /usr/irissys/csp/bin/CSP.ini
