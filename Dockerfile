FROM python:3.12

WORKDIR /app

COPY git-filter-repo ./

# The directory that will contain the git directory
# Must be set up using a volume
WORKDIR /workdir

ENTRYPOINT [ "python", "/app/git-filter-repo" ]
