#!/bin/bash
set -eo pipefail
echo "Begin - ${0##*/}"

# collect metadata
GIT_BRANCH="$(git branch --show-current)"
GIT_COMMIT="$(git rev-parse HEAD)"
GIT_TAG="$(git describe --tags --exact-match 2>/dev/null || :)"

export GIT_BRANCH GIT_COMMIT GIT_TAG

function build {
    FROM="$(grep -iP '^FROM' dockerfile | awk '{print $2}')"
    ee docker pull "$FROM"
    ee docker build -t "$GITHUB_REPOSITORY" \
        --build-arg '"BUILD_URL=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/job/$GITHUB_JOB"' \
        --build-arg "\"DIGEST=\$(docker inspect --format='{{index .RepoDigests 0}}' '$FROM' | sed 's/.*@//')\"" \
        --build-arg '"GIT_COMMIT=$GIT_COMMIT"' \
        --build-arg '"TIMESTAMP=$(date --rfc-3339 seconds)"' \
        --build-arg '"URL=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"' \
        --build-arg '"VENDOR=$GITHUB_REPOSITORY_OWNER"' \
        --build-arg '"VERSION=${GIT_TAG:-$GIT_BRANCH}"' \
        --progress plain .
    ee "docker inspect --format='{{json .Config.Labels}}' '$GITHUB_REPOSITORY' | jq"
}

function push {
    ee 'printf "$GITHUB_TOKEN" | wc -c'
    if [[ "$CI" == 'true' && "$ACT" != 'true' ]]; then
        PUSH='false'
        # Docker Hub
        if [[ -n "$DOCKERHUB_PASSWORD" ]]; then
            echo '##### Docker Hub #####'
            ee 'echo "$DOCKERHUB_PASSWORD" | docker login docker.io -u "$DOCKERHUB_USERNAME" --password-stdin'
            push_to 'docker.io'
            PUSH='true'
        else
            printf '\e[1;96mNOTICE: Skipping push to Docker Hub because DOCKERHUB_PASSWORD is not set.\e[0m\n'
        fi
        # GitHub Container Registry
        if [[ -n "$GITHUB_TOKEN" ]]; then
            echo '##### GitHub Container Registry #####'
            ee 'echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_REPOSITORY_OWNER" --password-stdin'
            push_to 'ghcr.io'
            PUSH='true'
        else
            printf '\e[1;96mNOTICE: Skipping push to GitHub Container Registry because GITHUB_TOKEN is not set.\e[0m\n'
        fi
        if [[ "$PUSH" != 'true' ]]; then
            printf '\e[1;91mERROR: No containers pushed!\e[0m\n'
            exit 1
        fi
    else
        printf '\e[1;96mNOTICE: Skipping "docker push" because this is not a cloud CI environment.\e[0m\n'
    fi
}

function push_to {
    echo "Push to $1."
    ee docker tag "$GITHUB_REPOSITORY" "$1/$GITHUB_REPOSITORY:$GIT_COMMIT"
    ee docker push "$1/$GITHUB_REPOSITORY:$GIT_COMMIT"
    if [[ -n "$GIT_BRANCH" ]]; then
        ee docker tag "$GITHUB_REPOSITORY" "$1/$GITHUB_REPOSITORY:$GIT_BRANCH"
        ee docker push "$1/$GITHUB_REPOSITORY:$GIT_BRANCH"
    fi
    if [[ -n "$GIT_TAG" ]]; then
        ee docker tag "$GITHUB_REPOSITORY" "$1/$GITHUB_REPOSITORY:$GIT_TAG"
        ee docker push "$1/$GITHUB_REPOSITORY:$GIT_TAG"
    fi
    if [[ "$GIT_BRANCH" == 'main' ]]; then
        ee docker tag "$GITHUB_REPOSITORY" "$1/$GITHUB_REPOSITORY:latest"
        ee docker push "$1/$GITHUB_REPOSITORY:latest"
    fi
}

if [[ "$1" == 'push' ]]; then
    push
else
    build
fi

echo "Done. - ${0##*/}"
