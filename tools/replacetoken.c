#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(const char *program)
{
    fprintf(stderr,
            "Usage: %s FROM TO [FROM TO ...]\n"
            "Reads stdin, replaces every occurrence, and writes stdout.\n",
            program);
}

static char *replace_all(const char *input, const char *from, const char *to)
{
    const size_t input_len = strlen(input);
    const size_t from_len = strlen(from);
    const size_t to_len = strlen(to);
    size_t count = 0;
    const char *cursor = input;
    const char *match = NULL;

    if (from_len == 0U) {
        errno = EINVAL;
        return NULL;
    }

    while ((match = strstr(cursor, from)) != NULL) {
        ++count;
        cursor = match + from_len;
    }

    if (count == 0U) {
        return strdup(input);
    }

    size_t output_len = input_len;
    if (to_len >= from_len) {
        const size_t growth = to_len - from_len;
        if (growth != 0U && count > (SIZE_MAX - output_len - 1U) / growth) {
            errno = EOVERFLOW;
            return NULL;
        }
        output_len += count * growth;
    } else {
        output_len -= count * (from_len - to_len);
    }

    char *output = malloc(output_len + 1U);
    if (output == NULL) {
        return NULL;
    }

    const char *read_ptr = input;
    char *write_ptr = output;
    while ((match = strstr(read_ptr, from)) != NULL) {
        const size_t prefix_len = (size_t)(match - read_ptr);
        memcpy(write_ptr, read_ptr, prefix_len);
        write_ptr += prefix_len;
        memcpy(write_ptr, to, to_len);
        write_ptr += to_len;
        read_ptr = match + from_len;
    }

    const size_t tail_len = strlen(read_ptr);
    memcpy(write_ptr, read_ptr, tail_len + 1U);
    return output;
}

int main(int argc, char **argv)
{
    if (argc < 3 || ((argc - 1) % 2) != 0) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    for (int index = 1; index < argc; index += 2) {
        if (argv[index][0] == '\0') {
            fprintf(stderr, "FROM token must not be empty.\n");
            return EXIT_FAILURE;
        }
    }

    char *line = NULL;
    size_t capacity = 0U;
    ssize_t length = 0;

    while ((length = getline(&line, &capacity, stdin)) >= 0) {
        (void)length;
        char *current = strdup(line);
        if (current == NULL) {
            perror("strdup");
            free(line);
            return EXIT_FAILURE;
        }

        for (int index = 1; index < argc; index += 2) {
            char *next = replace_all(current, argv[index], argv[index + 1]);
            free(current);
            if (next == NULL) {
                perror("replace_all");
                free(line);
                return EXIT_FAILURE;
            }
            current = next;
        }

        if (fputs(current, stdout) == EOF) {
            perror("stdout");
            free(current);
            free(line);
            return EXIT_FAILURE;
        }
        free(current);
    }

    if (ferror(stdin) != 0) {
        perror("stdin");
        free(line);
        return EXIT_FAILURE;
    }

    free(line);
    return EXIT_SUCCESS;
}
