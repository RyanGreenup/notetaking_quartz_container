FROM fedora:latest
RUN dnf install -y caddy  nodejs-npm git entr
RUN git clone https://github.com/jackyzha0/quartz
WORKDIR /quartz
RUN npm install
RUN npx quartz create -d "content" -X "new" -l "relative"
COPY Caddyfile .
COPY run_quartz.sh .
COPY loop_quartz.sh .
RUN chmod +x run_quartz.sh
RUN chmod +x loop_quartz.sh
