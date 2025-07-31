import { observer } from 'mobx-react-lite';
import { useStore } from '../stores';
import { useState, useEffect } from 'react';
import type { Project } from '../stores/ProjectStore';

const ProjectManager = observer(() => {
  const { projectStore } = useStore();
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newProjectName, setNewProjectName] = useState('');
  const [createLoading, setCreateLoading] = useState(false);

  useEffect(() => {
    projectStore.fetchProjects();
  }, [projectStore]);

  const handleCreateProject = async () => {
    if (!newProjectName.trim()) return;
    
    setCreateLoading(true);
    try {
      await projectStore.createProject(newProjectName.trim());
      setNewProjectName('');
      setShowCreateForm(false);
    } catch (error) {
      // Error is handled in the store
    } finally {
      setCreateLoading(false);
    }
  };

  const handleSelectProject = (project: Project) => {
    projectStore.setCurrentProject(project);
  };

  const handleDeleteProject = async (project: Project) => {
    if (window.confirm(`Are you sure you want to delete "${project.name}"?`)) {
      try {
        await projectStore.deleteProject(project.id);
      } catch (error) {
        // Error is handled in the store
      }
    }
  };

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString('he-IL');
  };

  return (
    <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-semibold">Projects</h3>
        <button
          onClick={() => setShowCreateForm(true)}
          className="px-3 py-1 text-sm bg-green-600 hover:bg-green-700 rounded transition-colors"
        >
          New Project
        </button>
      </div>

      {/* Create Project Form */}
      {showCreateForm && (
        <div className="mb-4 p-3 bg-gray-700 rounded border border-gray-600">
          <div className="flex gap-2 mb-2">
            <input
              type="text"
              value={newProjectName}
              onChange={(e) => setNewProjectName(e.target.value)}
              placeholder="Project name"
              className="flex-1 p-2 text-sm bg-gray-600 border border-gray-500 rounded focus:outline-none focus:border-blue-500"
              disabled={createLoading}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  handleCreateProject();
                } else if (e.key === 'Escape') {
                  setShowCreateForm(false);
                  setNewProjectName('');
                }
              }}
            />
            <button
              onClick={handleCreateProject}
              disabled={createLoading || !newProjectName.trim()}
              className="px-3 py-2 text-sm bg-blue-600 hover:bg-blue-700 disabled:bg-gray-600 disabled:cursor-not-allowed rounded transition-colors"
            >
              {createLoading ? '...' : 'Create'}
            </button>
            <button
              onClick={() => {
                setShowCreateForm(false);
                setNewProjectName('');
              }}
              disabled={createLoading}
              className="px-3 py-2 text-sm bg-gray-600 hover:bg-gray-700 rounded transition-colors"
            >
              ✕
            </button>
          </div>
        </div>
      )}

      {/* Current Project */}
      {projectStore.currentProject && (
        <div className="mb-4 p-3 bg-blue-900/50 border border-blue-700 rounded">
          <div className="flex justify-between items-center">
            <div>
              <div className="text-sm text-blue-300">Current Project</div>
              <div className="font-medium">{projectStore.currentProject.name}</div>
              <div className="text-xs text-gray-400">
                Last modified: {formatDate(projectStore.currentProject.updatedAt)}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Projects List */}
      <div className="space-y-2">
        {projectStore.loading && (
          <div className="text-sm text-gray-400 text-center py-4">
            Loading projects...
          </div>
        )}

        {projectStore.error && (
          <div className="text-sm text-red-400 bg-red-900/20 border border-red-700 rounded p-2">
            {projectStore.error}
          </div>
        )}

        {!projectStore.loading && !projectStore.error && projectStore.projects.length === 0 && (
          <div className="text-sm text-gray-400 text-center py-4">
            No projects yet
          </div>
        )}

        {projectStore.projects.map((project) => (
          <div
            key={project.id}
            className={`p-3 rounded border cursor-pointer transition-colors ${
              projectStore.currentProject?.id === project.id
                ? 'bg-blue-900/30 border-blue-600'
                : 'bg-gray-700 border-gray-600 hover:bg-gray-650 hover:border-gray-500'
            }`}
            onClick={() => handleSelectProject(project)}
          >
            <div className="flex justify-between items-start">
              <div className="flex-1 min-w-0">
                <div className="font-medium truncate">{project.name}</div>
                {project.description && (
                  <div className="text-xs text-gray-400 truncate">{project.description}</div>
                )}
                <div className="text-xs text-gray-500 mt-1">
                  {formatDate(project.updatedAt)}
                </div>
              </div>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  handleDeleteProject(project);
                }}
                className="ml-2 p-1 text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded transition-colors"
                title="Delete Project"
              >
                🗑️
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
});

export default ProjectManager;