# Official versioned Rocker image, inspected 2026-09-25.
FROM rocker/shiny:4.6.1@sha256:679ac44ec3d502474d3d55d1ea103528abd88fd32812f851bf388d4dfe5777ed
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev libssl-dev && rm -rf /var/lib/apt/lists/*
RUN Rscript -e 'install.packages(c("DBI","uuid","zip","RPostgres","openssl"),repos="https://cloud.r-project.org",Ncpus=4)'
COPY packages/delphyr /tmp/delphyr
COPY packages/delphyrApp /tmp/delphyrApp
RUN R CMD INSTALL /tmp/delphyr /tmp/delphyrApp && rm -rf /tmp/delphyr /tmp/delphyrApp
COPY deploy/auth/shiny-server.conf /etc/shiny-server/shiny-server.conf
COPY deploy/auth/app.R /srv/shiny-server/delphyr/app.R
# The image's prebuilt fs package links to the system libuv runtime.
RUN apt-get update && apt-get install -y --no-install-recommends libuv1t64 && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /srv/shiny-server/delphyr/app_cache \
    && chown shiny:shiny /srv/shiny-server/delphyr/app_cache
COPY deploy/auth/run-direct.R /srv/shiny-server/delphyr/run-direct.R
