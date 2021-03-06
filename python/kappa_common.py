""" Shared functions of api client for the kappa programming language
"""

import json

class FileMetadata(object):

    def __init__(self,
                 file_metadata_id,
                 file_metadata_position,
                 file_metadata_compile = True ,
                 file_metadata_hash = None ,
                 file_version = []):
        self.file_metadata_id = file_metadata_id
        self.file_metadata_position = file_metadata_position
        self.file_metadata_compile = file_metadata_compile
        self.file_metadata_hash = file_metadata_hash
        self.file_version = file_version
    def toJSON(self):
        return({ "file_metadata_compile" : self.file_metadata_compile ,
                 "file_metadata_hash" : self.file_metadata_hash ,
                 "file_metadata_id" : self.file_metadata_id ,
                 "file_metadata_position" : self.file_metadata_position ,
                 "file_metadata_version" : self.file_version })

    def get_file_id(self):
        return(self.file_metadata_id)

class File(object):

    def __init__(self,
                 file_metadata,
                 file_content):
        self.file_metadata = file_metadata
        self.file_content = file_content

    def toJSON(self):
        return({ "file_metadata" : self.file_metadata.toJSON() ,
                 "file_content" : self.file_content })

    def get_file_id(self):
        return(self.file_metadata.get_file_id())
    def get_content(self):
        return(self.file_content)

def hydrate_file (info):
    return(File(info["file_metadata"],
                info["file_content"]))

class SimulationParameter(object):

    def __init__(self,
                 simulation_plot_period,
                 simulation_id,
                 simulation_pause_condition,
                 simulation_seed = None,
                 simulation_store_trace = False) :
        self.simulation_plot_period = simulation_plot_period
        self.simulation_id = simulation_id
        self.simulation_pause_condition = simulation_pause_condition
        self.simulation_seed = simulation_seed
        self.simulation_store_trace = simulation_store_trace

    def toJSON(self):
        return({ "simulation_plot_period" : self.simulation_plot_period,
                 "simulation_id" : self.simulation_id,
                 "simulation_pause_condition": self.simulation_pause_condition ,
                 "simulation_store_trace": self.simulation_store_trace ,
                 "simulation_seed" : self.simulation_seed })

class PlotLimit(object):

    def __init__(self,
                 plot_limit_offset,
                 plot_limit_points = None) :
        self.plot_limit_offset = plot_limit_offset
        self.plot_limit_points = plot_limit_points

    def toURL(self):

        if self.plot_limit_offset :
            url_plot_limit_offset = "&plot_limit_offset={0}".format(self.plot_limit_offset)
        else :
            url_plot_limit_offset = ""

        if self.plot_limit_points :
            url_plot_limit_points = "&plot_limit_points={0}".format(self.plot_limit_points)
        else :
            url_plot_limit_points = ""

        url_plot_limit = "{0}{1}".format(url_plot_limit_offset,
                                         url_plot_limit_points)
        return url_plot_limit

    def toJSON(self):
        return({ "plot_limit_offset" : self.plot_limit_offset ,
                 "plot_limit_points" : self.plot_limit_points })

class PlotParameter(object):
    def __init__(self,
                 plot_parameter_plot_limit = None) :
        self.plot_parameter_plot_limit = plot_parameter_plot_limit

    def toJSON(self):
        if self.plot_parameter_plot_limit :
            limit = self.plot_parameter_plot_limit.toJSON()
        else:
            limit =  None
        return({ "plot_parameter_plot_limit" : limit })

    def toURL(self):
        if self.plot_parameter_plot_limit :
            url = self.plot_parameter_plot_limit.toURL()
        else:
            url = ""
        return url

class KappaError(Exception):
    """ Error returned from the Kappa server
    """
    def __init__(self, errors):
        Exception.__init__(self)
        self.errors = errors
