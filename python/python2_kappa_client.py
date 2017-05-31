""" Web api client for the kappa programming language
"""

import sys
import getopt
import time
import uuid
import kappa_common
import kappa_std

def main():
    # command line
    argv = sys.argv[1:]
    cmd = "kappa_client.py"

    # default arguments
    inputfile = None  # if missing input file just get version
    url = "../bin/KaSimAgent"
    pause_condition = "[false]"
    plot_period = 0.1
    seed = None

    help_line= (cmd
                + ' -k <kappafile> '
                + ' -u <url or path to stdsim> '
                + ' -t <max_time> '
                + ' -e <max_events> '
                + ' -pp <plot_period> '
                + ' -s <random_seed> ')

    try:
        opts, args = getopt.getopt(argv,
                                   "h:k:u:t:e:pp:s",
                                   ["help","kappafile=",
                                    "url=",
                                    "max_time=",
                                    "max_event=",
                                    "plot_period=",
                                    "seed=", ])
    except:
        print(help_line)
        sys.exit(2)

    for opt, arg in opts:
        if opt in ('-h',"--help"):
            print(help_line)
            sys.exit()
        elif opt in ("-k", "--kappafile"):
            inputfile = arg
        elif opt in ("-u", "--url"):
            url = arg
        elif opt in ("-t", "--max_time"):
            pause_condition = "[T]>"+arg+" || "+pause_condition
        elif opt in ("-e", "--max_events"):
            pause_condition = "[E]>"+arg+" || "+pause_condition
        elif opt in ("-pp", "--plot_period"):
            plot_period = float(arg)
        elif opt in ("-s", "--seed"):
            seed = int(arg)

    print('Input file is : {0} '.format(inputfile))
    print('Endpoint url : {0} '.format(url))
    print('Pause conditon : {0}'.format(pause_condition))
    print('Plot period : {0} '.format(plot_period))
    print('Random seed : {0} '.format(seed))

    try:
        runtime = kappa_std.KappaStd(url)
        project_id = str(uuid.uuid1())
        runtime.project_create(project_id)
        print("project_id : {0}".format(project_id))
        if inputfile:
            with open(inputfile) as f:
                code = f.read()
                file_content = str(code)
                file_metadata = kappa_common.FileMetadata(inputfile,0)
                file_object = kappa_common.File(file_metadata,file_content)
                runtime.file_create(project_id,file_object)
                runtime.project_parse(project_id)
                simulation_id = str(uuid.uuid1())
                print("simulation_id : {0}".format(simulation_id))


                end_time = 10.0
                simulation_parameter = kappa_common.SimulationParameter(plot_period,
                                                                        simulation_id,
                                                                        pause_condition,
                                                                        seed)
                runtime.simulation_start(project_id,simulation_parameter)

                simulation_info = runtime.simulation_info(project_id)

                while simulation_info["simulation_info_progress"]["simulation_progress_is_running"] :
                    time.sleep(1)

                    percentage = ""
                    time_percentage = simulation_info["simulation_info_progress"]["simulation_progress_time_percentage"]
                    event_percentage = simulation_info["simulation_info_progress"]["simulation_progress_event_percentage"]

                    if time_percentage or time_percentage == 0 :
                        percentage = time_percentage
                    if event_percentage or event_percentage == 0 :
                        percentage = event_percentage

                    sys.stdout.write("..{0}.. ".format(percentage))
                    sys.stdout.flush()
                    simulation_info = runtime.simulation_info(project_id)

                print("")
                print("info")
                print(simulation_info)
                plot_detail = runtime.simulation_detail_plot(project_id)
                print("plot")
                print(plot_detail)
        else:
            print(runtime.info())
    except kappa_common.KappaError as exception:
        print(exception.errors)
    return None
    None

if __name__ == "__main__":
    main()