import { Router } from 'express';
import { 
  ItemController, 
  ProjectController, 
  MessageController, 
  AIController, 
  GameController 
} from '../controllers';

const router = Router();

router.get('/items', ItemController.getItems);
router.post('/items', ItemController.createItem);

router.get('/projects', ProjectController.getProjects);
router.post('/projects', ProjectController.createProject);
router.put('/projects/:id', ProjectController.updateProject);
router.delete('/projects/:id', ProjectController.deleteProject);

router.get('/projects/:id/messages', MessageController.getMessages);

router.post('/projects/:id/messages', MessageController.createMessage);
router.delete('/projects/:id/messages', MessageController.clearMessages);

router.post('/ai/generate', AIController.generate);

router.post('/games/share', GameController.shareGame);
router.get('/games/shared', GameController.getUserSharedGames);
router.delete('/games/:shareId', GameController.deleteSharedGame);

export { router as protectedRoutes };