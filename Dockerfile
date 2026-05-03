FROM ghcr.io/foundry-rs/foundry:latest

USER root
RUN mkdir -p /data && chown -R foundry:foundry /data
USER foundry

COPY --chown=foundry:foundry entrypoint.sh /usr/local/bin/entrypoint.sh

VOLUME ["/data"]
EXPOSE 8545
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
