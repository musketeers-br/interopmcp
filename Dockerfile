ARG IMAGE=docker.iscinternal.com/docker-intersystems/intersystems/iris-community:2027.1.0AI.109.0
FROM $IMAGE 

WORKDIR /home/irisowner

ARG NAMESPACE="IRISAPP"

## Embedded Python environment
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

RUN --mount=type=bind,src=.,dst=/home/irisowner/dev \
    iris start IRIS && \
    iris merge IRIS /home/irisowner/dev/merge.cpf && \
	iris session IRIS < /home/irisowner/dev/iris.script && \
    iris stop IRIS quietly