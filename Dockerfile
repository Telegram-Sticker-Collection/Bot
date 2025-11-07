FROM alpine:3.22

RUN apk fix && \
    apk --no-cache --update add git git-lfs gpg less openssh patch perl curl bash && \
    git lfs install

WORKDIR /app
COPY bot.sh .

CMD ["bash", "bot.sh"]