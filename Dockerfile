FROM alpine:3.22

RUN apk fix && \
    apk --no-cache --update add git git-lfs gpg less openssh patch perl curl bash jq && \
    git lfs install

RUN git config --global user.name "Telegram Sticker Collection Bot"
RUN git config --global user.email "TelegramStickerCollectionBot@nowhere.nowhere"

WORKDIR /app
COPY bot.sh .

CMD ["bash", "bot.sh"]