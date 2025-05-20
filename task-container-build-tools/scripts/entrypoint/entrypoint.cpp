// entrypoint.cpp by Isa Aguilar
// Compile in alpine by running one of the following:
// #1) clang++:
//   clang++ -std=c++17 entrypoint.cpp -lcurl -o entrypoint
// #2) g++:
//   g++ -std=c++17 entrypoint.cpp -lcurl -o entrypoint
#include <ctime>
#include <iostream>
#include <regex>
#include <vector>
#include <string>
#include <filesystem>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <sys/types.h>
#include <pwd.h>
#include <uuid/uuid.h>

// Non standard lib. Compile with `-lcurl`
#include <curl/curl.h>

// Add stdarg.h to compile on alpine --
#include <stdarg.h>

struct download_status {
    FILE* fp;
    size_t download_total;
};

void LogInfo(const char* format, ...) {
    time_t now;
    time(&now);
    char buf[sizeof "2011-10-08T07:07:09Z"];
    strftime(buf, sizeof buf, "%FT%TZ", gmtime(&now));

    std::cout << buf << " ";
    va_list args;
    va_start(args, format);
    vprintf(format, args);
    va_end(args);

    std::cout << std::endl;
    return;
}

char* env_or_panic(const char* name, bool isRequired) {
    char* env = getenv( name );
    if (env == NULL && isRequired) {
        LogInfo("'%s' env is required\n", name);
        exit(1);
    }
    return env;
}

bool user_exists() {
    int bufsize = 1024;
    char buffer[bufsize];
    struct passwd pwd, *result = NULL;
    if (getpwuid_r(getuid(), &pwd, buffer, bufsize, &result) != 0 || !result) {
        return false;
    }
    return true;
}

static size_t write_data(void* ptr, size_t sizeOfItem, size_t numOfItems, download_status *stream) {
    download_status *status = stream;
    size_t written = fwrite(ptr, sizeOfItem, numOfItems, status->fp);
    status->download_total += written;
    // TODO think of a good way to show download status
    // printf("\r%ld bytes        ", status->download_total);
    // fflush(stdout);
    return written;
}

bool download_file(char* url, char* filename) {
    LogInfo("Downloading %s", url);
    FILE* fp = fopen(filename, "wb");
    if (!fp) {
        fprintf(stderr, "Failed to open file for write: '%s'", filename);
        return false;
    }

    CURL* handle = curl_easy_init();

    curl_easy_setopt(handle, CURLOPT_URL, url);
    curl_easy_setopt(handle, CURLOPT_VERBOSE, 0L);
    curl_easy_setopt(handle, CURLOPT_NOPROGRESS, 1L);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, write_data);
    curl_easy_setopt(handle, CURLOPT_FAILONERROR, 1L);

    download_status status;
    status.download_total = 0;
    status.fp = fp;
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &status);
    bool success;
    int retval = curl_easy_perform(handle);
    if (retval != 0) {
        LogInfo("Download failed");
        success = false;
    } else {
        LogInfo("File saved to %s", filename);
        success = true;
    }
    curl_easy_cleanup(handle);

    fclose(fp);
    if (!success) {
        remove(filename);
        exit(1);
    }
    return success;
}

bool is_dir(char* filename) {
    struct stat dat;
    if (stat(filename, &dat) != 0) {
        return false;
    }
    if (! dat.st_mode & S_IFDIR ) {
        return false;
    }
    // Is a valid directory
    return true;
}

bool check_set_exec_script(char* filename, char* exec_script) {
    struct stat dat;
    if (stat(filename, &dat) != 0) {
        return false;
    }
    if( dat.st_mode & S_IFDIR ) {
        return false;
    }
    if (dat.st_size == 0) {
        return false;
    }
    LogInfo("Execution script mounted from ConfigMap");
    int src = open(filename, O_RDONLY);
    int dst = open(exec_script, O_WRONLY | O_CREAT, 0777);
    char temp;
    while (read(src, &temp, sizeof(temp)) == sizeof(temp)) {
        write(dst, &temp, sizeof(temp));
    }
    close(src);
    close(dst);
    return true;
}

int get_current_rerun(char* infra3_generation_path, const char* infra3_task) {
    // First we have to know the order of task execution
    const int total_tasks = 10;
    const std::vector<std::string> tasks =  {
		"setup",
		"preinit", "init", "postinit",
		"preplan", "plan", "postplan",
		"preapply", "apply", "postapply"
    };

    int task_index = -1;
    for(int i=0; i < total_tasks; i++) {
        if (tasks[i] == infra3_task) {
            task_index = i;
            break;
        }
    }
    if (task_index == -1) {
        return 10;
    }

    int highest = 0;
	int prev_task_highest = -1;
	int next_task_highest = -1;
	int infra3_task_highest = -1;

    DIR* dir = opendir(infra3_generation_path);
    if (dir == NULL) {
        return 20;
    }

    int total_files = 0;
    std::vector<std::string> files;
    struct dirent *ent;;
    while ((ent = readdir(dir)) != NULL) {
        if (ent->d_type == DT_DIR) {
            continue;
        }
        ++total_files;
        files.push_back(ent->d_name);
    }
    closedir (dir);
    for(int i=0; i < total_tasks; ++i) {
        int temp_highest = -1;
        std::string task = tasks[i];
        // format_1 will contain the uuid: '<task>.<rerun>.<uuid>.out'
        // UUIDs are written in 5 groups of hexadecimal digits separated by hyphens.
        // The length of each group is: 8-4-4-4-12.
        // UUIDs are fixed length.
        // For example: 123e4567-e89b-12d3-a456-426655440000
        // UUIDs have 32 digits plus 4 hyphens for a total of 36 characters.
        std::regex format_1("^"+task+".([0-9]+).[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}.out");
        // format_2 is for compatibility with pre-metadata filenames like format_1
        std::regex format_2("^"+task+".out");

        for(int f=0; f < total_files; ++f) {
            std::smatch match;
            if (std::regex_search(files[f], match, format_1)) {
                // for (size_t i = 0; i < match.size(); ++i) {
                //     std::cout << i << ": '" << match[i].str() << "'\n";
                // }
                // There is only a single group match which is index 1
                if (temp_highest < std::stoi(match[1])) {
                    temp_highest = std::stoi(match[1]);
                }

            } else if (std::regex_search(files[f], match, format_2)) {
                if (0 > temp_highest) {
                    temp_highest = 0;
                }
            }
        }
        if (i < task_index) {
            if (temp_highest > prev_task_highest) {
                prev_task_highest = temp_highest;
            }
        } else if (i == task_index) {
            if (temp_highest > infra3_task_highest) {
                infra3_task_highest = temp_highest;
            }
        } else if (i > task_index) {
            if (temp_highest > next_task_highest) {
                next_task_highest = temp_highest;
            }
        }
    }

    highest = infra3_task_highest + 1;
    if (prev_task_highest > infra3_task_highest) {
        highest = prev_task_highest;
    }
    if (next_task_highest > infra3_task_highest) {
        highest = next_task_highest + 1;
    }
    return highest;
}

int run() {
    if (!user_exists()) {
        char* passwd = env_or_panic("PASSWD", false);
        if (!passwd) {
            passwd = "/etc/passwd";
        }
        int result = access(passwd, W_OK);
        if (result == 0){
            char* home = env_or_panic("HOME", true);
            char* username = env_or_panic("USER_NAME", false);
            if (username == NULL) {
                username = "i3-runner";
            }

            FILE * fp = fopen(passwd, "a");
            fprintf(fp, "%s:x:%d:%d:%s user:%s:/sbin/nologin\n", username, getuid(), getgid(), username, home);
            fclose(fp);
        }
    }

    char* infra3_task                             = env_or_panic("I3_TASK", true);
    char* infra3_generation                       = env_or_panic("I3_GENERATION", true);
    char* infra3_generation_path                  = env_or_panic("I3_GENERATION_PATH", true);
    char* infra3_main_module_addons               = env_or_panic("I3_MAIN_MODULE_ADDONS", false);
    char* infra3_main_module                      = env_or_panic("I3_MAIN_MODULE", true);
    char* infra3_task_exec_inline_source_file     = env_or_panic("I3_TASK_EXEC_INLINE_SOURCE_FILE", false);
    char* infra3_task_exec_config_map_source_path = env_or_panic("I3_TASK_EXEC_CONFIGMAP_SOURCE_PATH", false);
    char* infra3_task_exec_config_map_source_key  = env_or_panic("I3_TASK_EXEC_CONFIGMAP_SOURCE_KEY", false);
    char* infra3_task_exec_url_source             = env_or_panic("I3_TASK_EXEC_URL_SOURCE", false);
    char* pod_uid                              = env_or_panic("POD_UID", false);

    std::filesystem::create_directories(infra3_generation_path);
    int current_rerun = get_current_rerun(infra3_generation_path, infra3_task);
    LogInfo("Generation #%s Run: #%d", infra3_generation, current_rerun);

    // The exec script path/filename -> will be created
    char exec_script[128];
    sprintf(exec_script, "%s/%s.sh", infra3_generation_path, infra3_task);
    // Path where the inline script exists
    char inline_source[128];
    sprintf(inline_source, "%s/%s", infra3_main_module_addons, infra3_task_exec_inline_source_file);
    // Path where the script via the ConfigMap exists
    char config_map_source[128];
    sprintf(config_map_source, "%s/%s", infra3_task_exec_config_map_source_path, infra3_task_exec_config_map_source_key);

    if (! check_set_exec_script(inline_source, exec_script)) {
        if (! check_set_exec_script(config_map_source, exec_script)) {
            download_file(infra3_task_exec_url_source, exec_script);
        }
    }

    LogInfo("Executing %s", exec_script);

    // Change directory into the infra3_main_module when it exists
    if (is_dir(infra3_main_module)) {
        if (chdir(infra3_main_module) == -1) {
            LogInfo("Cannot change directory into %s", infra3_main_module);
            return 127;
        }
    }

    int fd[2];
    if (pipe(fd) == -1) {
        LogInfo("Opening pipe failed");
        return 2;
    }
    int id = fork();
    if (id == -1) {
        return 1;
    }
    if (id == 0) {
        close(fd[0]);
        dup2(fd[1], STDOUT_FILENO);
        dup2(fd[1], STDERR_FILENO);
        close(fd[1]);
        char* args[3] = {"/bin/bash", exec_script, NULL};

        int e = execv(args[0], args);
        if (e != 0) {
            LogInfo("The command failed");
            return 1;
        }
    } else {
        close(fd[1]);
        char logfile[128];
        sprintf(logfile, "%s/%s.%d.%s.out", infra3_generation_path, infra3_task, current_rerun, pod_uid);
        int type = open(logfile, O_WRONLY | O_CREAT, 0777);
        if (type == -1) {
            LogInfo("Failed to open log.out in child process");
            return 1;
        }
        LogInfo("Logging to %s", logfile);
        LogInfo("Streaming results from execution:");

        std::string out;
        char temp;
        while (read(fd[0], &temp, sizeof(temp)) == sizeof(temp)) {
            std::cout << temp;
            out = out + temp;
            write(type, &temp, sizeof(temp));
        }
        close(type);
        std::cout << std::endl;
    }
    int status;
    wait(&status);
    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }
    if (WIFSIGNALED(status)) {
        LogInfo("The process ended with kill -%d.\n", WTERMSIG(status));
    }
    return 1;
}

int main(){
    return run();
}
