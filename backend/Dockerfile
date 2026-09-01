FROM mcr.microsoft.com/playwright:v1.60.0-jammy

WORKDIR /app

COPY package*.json ./

RUN npm install

# Rewrites generated PDFs into one standards-compliant revision so Safari,
# Edge, WPS, Chrome, and Brave all render the same pages.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ghostscript poppler-utils \
    && rm -rf /var/lib/apt/lists/*

COPY . .

EXPOSE 8080

CMD ["npm", "start"]
